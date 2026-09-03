# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'timeout'
require 'fileutils'
require 'yaml'

# 16-01 T-16-01..03 / Pitfall 1-4, as specs: the shared Config
# mutator's write path -- flock on the inode-stable SIDECAR (never the
# yml inode the rename replaces; 16-RESEARCH PROBED P5/P6), the fresh
# in-lock re-read that kills the stale-snapshot clobber (P3), the
# key-level ASSIGN that keeps DEFAULT_CONFIG pristine (Pitfall 3), the
# atomic tmp+rename save, and release-on-raise. Hermetic: tmpdir
# projects, no server, no CLI, no real ~/.spm-cache. Every
# cross-process row forks a REAL child (the build_lock_spec idiom) --
# a same-process second flock on the same file is granted by the OS
# and would prove nothing.
RSpec.describe SPMCache::Core::Config, 'shared config mutator (16-01)' do
  let(:project_dir) { Dir.mktmpdir('spm-cache-mutator') }
  let(:config) { described_class.instance }

  around do |example|
    previous_project_dir = config.project_dir
    previous_config_path = config.config_path
    described_class.configure(project_dir: project_dir)
    config.reset!
    example.run
  ensure
    config.reset!
    # Restore BOTH: configure re-derives config_path from project_dir,
    # so the explicit previous path must ride along to restore exactly.
    described_class.configure(project_dir: previous_project_dir, config_path: previous_config_path)
    FileUtils.rm_rf(project_dir)
  end

  def write_config(ignore:, mode: nil)
    path = File.join(project_dir, 'spm-cache.yml')
    File.write(path, YAML.dump(SPMCache::Core::Config::DEFAULT_CONFIG.dup.merge('ignore' => ignore)))
    File.chmod(mode, path) if mode
    path
  end

  # The on-disk truth, parsed whole: a truncated file would fail here.
  def disk_ignore
    YAML.safe_load(File.read(File.join(project_dir, 'spm-cache.yml')))['ignore']
  end

  def sidecar_path
    File.join(project_dir, 'spm-cache.yml.lock')
  end

  # A forked child probes the sidecar non-blocking and reports the
  # verdict: 'free' or 'held'. LOCK_NB returns false under contention
  # and never raises (PROBED P4) -- the verdict is truthiness.
  def sidecar_probe_from_child
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      f = File.open(sidecar_path, File::CREAT | File::RDWR)
      acquired = f.flock(File::LOCK_EX | File::LOCK_NB) != false
      writer.write(acquired ? 'free' : 'held')
      writer.close
      f.flock(File::LOCK_UN)
      f.close
    end
    writer.close
    verdict = reader.read
    reader.close
    Process.wait(pid)
    verdict
  end

  # A forked child holds an exclusive flock on the sidecar for
  # `hold` seconds, signalling the parent once the lock is genuinely
  # held (the build_lock_spec pipe idiom).
  def hold_sidecar_in_child(hold:)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      f = File.open(sidecar_path, File::CREAT | File::RDWR)
      f.flock(File::LOCK_EX)
      writer.write 'locked'
      writer.close
      sleep hold
      f.flock(File::LOCK_UN)
      f.close
    end
    writer.close
    reader.read # blocks until the child confirms it holds the lock
    reader.close
    pid
  end

  describe 'add and remove' do
    it 'appends the exact entry on not-cached and removes exactly that entry on cached, leaving globs untouched' do
      write_config(ignore: ['Test*', 'Kept'])

      expect(config.set_ignored('Alamofire', true)).to eq(['Test*', 'Kept', 'Alamofire'])
      expect(disk_ignore).to eq(['Test*', 'Kept', 'Alamofire'])

      config.set_ignored('Alamofire', false)
      expect(disk_ignore).to eq(['Test*', 'Kept'])
    end
  end

  describe 'the batch mutator' do
    it 'applies every change under ONE lock acquisition -- a batch would self-deadlock if it re-locked per element' do
      write_config(ignore: [])

      # Timeout is the observable-consequence assertion: a per-element
      # re-entrant lock acquisition on a second fd BLOCKS forever in
      # the same process, so completing inside the bound proves the
      # single acquisition without peeking at internals.
      result = Timeout.timeout(5) { config.set_ignored_all('Alamofire' => true, 'SnapKit' => true, 'Ziph' => true) }
      expect(result).to eq(%w[Alamofire SnapKit Ziph])
      expect(disk_ignore).to eq(%w[Alamofire SnapKit Ziph])

      Timeout.timeout(5) { config.set_ignored_all('Alamofire' => false, 'Ziph' => false) }
      expect(disk_ignore).to eq(['SnapKit'])
    end
  end

  describe 'the lock target is the SIDECAR' do
    it 'creates the sidecar beside the config and refuses a cross-process non-blocking probe -- a false verdict, never a raise (P4)' do
      write_config(ignore: [])
      config.set_ignored('Alamofire', true)

      expect(config.config_lock_path).to eq(sidecar_path)
      expect(File.exist?(sidecar_path)).to be true

      pid = hold_sidecar_in_child(hold: 0.3)

      probe = File.open(sidecar_path, File::CREAT | File::RDWR)
      expect(probe.flock(File::LOCK_EX | File::LOCK_NB)).to eq(false) # TRUTHINESS: false, no exception

      Process.wait(pid)
      expect(probe.flock(File::LOCK_EX | File::LOCK_NB)).to eq(0) # free again after release
      probe.flock(File::LOCK_UN)
      probe.close
    end

    it 'defers a concurrent mutation while another process holds the sidecar, then lands (blocking flock)' do
      write_config(ignore: ['Existing'])
      pid = hold_sidecar_in_child(hold: 0.4)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Timeout.timeout(5) { config.set_ignored('NewPkg', true) }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      Process.wait(pid)

      expect(elapsed).to be >= 0.3 # the OS blocked us until the child released
      expect(disk_ignore).to eq(%w[Existing NewPkg])
    end

    it 'is inode-stable where the config is not: a rename-replace orphans no sidecar lock (P5/P6)' do
      write_config(ignore: [])
      path = File.join(project_dir, 'spm-cache.yml')
      config.set_ignored('Alamofire', true)

      config_inode = File.stat(path).ino
      sidecar_inode = File.stat(sidecar_path).ino

      # The mutator's save really replaces the config inode...
      config.set_ignored('SnapKit', true)
      expect(File.stat(path).ino).not_to eq(config_inode)
      # ...while the sidecar is inode-stable across rewrites.
      expect(File.stat(sidecar_path).ino).to eq(sidecar_inode)

      pid = hold_sidecar_in_child(hold: 0.4)

      # The lock-free public #save replaces the config UNDERNEATH the
      # held sidecar lock (the rename half in isolation).
      config.raw['ignore'] = %w[Alamofire SnapKit Ziph]
      config.save

      sidecar_probe = File.open(sidecar_path, File::CREAT | File::RDWR)
      expect(sidecar_probe.flock(File::LOCK_EX | File::LOCK_NB)).to eq(false) # P6: the held lock SURVIVED the replace
      config_probe = File.open(path, File::CREAT | File::RDWR)
      expect(config_probe.flock(File::LOCK_EX | File::LOCK_NB)).to eq(0) # P5 contrast: the replaced yml inode carries no lock
      config_probe.flock(File::LOCK_UN)
      config_probe.close

      Process.wait(pid)
      sidecar_probe.close # never acquired: nothing to unlock
    end
  end

  describe 'clobber-proofing (P3 as a regression pin)' do
    it 're-reads INSIDE the lock: a mutation against a stale snapshot cannot discard a concurrent writer\'s entry' do
      write_config(ignore: ['Existing'])
      config.load # the boot-time snapshot: ignore ['Existing']

      # Another writer (a CLI process) edits the file AFTER the
      # snapshot was taken. Against the pre-refactor write path
      # (load-then-merge-then-save from the snapshot) this entry is
      # silently lost; the mutator must keep BOTH.
      other = YAML.safe_load(File.read(config.config_path))
      other['ignore'] = %w[Existing OtherWriter]
      File.write(config.config_path, YAML.dump(other))

      config.set_ignored('NewPkg', true)
      expect(disk_ignore).to eq(%w[Existing OtherWriter NewPkg])
    end
  end

  describe 'atomicity' do
    it 'replaces by tmp+rename: the inode changes across a save, no temp files remain, and an existing mode survives' do
      write_config(ignore: [], mode: 0o600)
      path = File.join(project_dir, 'spm-cache.yml')
      inode = File.stat(path).ino

      config.set_ignored('Alamofire', true)

      expect(File.stat(path).ino).not_to eq(inode)                    # rename replaced the directory entry
      expect(File.stat(path).mode & 0o777).to eq(0o600)               # permissions preserved across the replace
      expect(Dir.children(project_dir).sort).to eq(                   # nothing left over in the dir
        ['spm-cache.yml', 'spm-cache.yml.lock']
      )
      expect(disk_ignore).to eq(['Alamofire'])                        # whole-file parse: never a truncated read
    end
  end

  describe 'purity (Pitfall 3)' do
    it 'keeps DEFAULT_CONFIG pristine and a freshly reset Config carries no entries -- assignment, never in-place' do
      # The never-loaded instance: raw['ignore'] IS DEFAULT_CONFIG's
      # shared inner array right now -- the exact pollution vector.
      config.reset!
      config.set_ignored('Alamofire', true)
      expect(SPMCache::Core::Config::DEFAULT_CONFIG['ignore']).to eq([])

      write_config(ignore: ['Existing'])
      config.set_ignored_all('NewPkg' => true, 'Glob*' => true)
      expect(SPMCache::Core::Config::DEFAULT_CONFIG['ignore']).to eq([])

      config.reset!
      expect(config.ignore_list).to eq([])
      expect(config.raw['ignore']).to eq([])
    end
  end

  describe 'release-on-raise' do
    it 'propagates the failed write AND frees the sidecar: a cross-process probe acquires afterwards' do
      write_config(ignore: [])
      config.set_ignored('Alamofire', true) # the sidecar now exists
      restricted = false

      FileUtils.chmod(0o500, project_dir) # tempfile creation inside the dir now fails
      restricted = true
      expect { config.set_ignored('SnapKit', true) }.to raise_error(Errno::EACCES)
      FileUtils.chmod(0o700, project_dir)
      restricted = false

      expect(sidecar_probe_from_child).to eq('free')
    ensure
      FileUtils.chmod(0o700, project_dir) if restricted
    end
  end

  describe 'path derivation (T-16-06)' do
    it 're-derives the config path from the configured project_dir; an explicit config_path still wins' do
      other = Dir.mktmpdir('spm-cache-mutator-other')
      begin
        described_class.configure(project_dir: other)
        expect(config.config_path).to eq(File.join(other, 'spm-cache.yml'))
        expect(config.config_lock_path).to eq(File.join(other, 'spm-cache.yml.lock'))

        config.set_ignored('Alamofire', true)
        expect(YAML.safe_load(File.read(File.join(other, 'spm-cache.yml')))['ignore']).to eq(['Alamofire'])
        # The mutation wrote inside the configured project and NOWHERE
        # else -- the around-hook project never saw a file.
        expect(File.exist?(File.join(project_dir, 'spm-cache.yml'))).to be false

        explicit = File.join(other, 'custom.yml')
        described_class.configure(project_dir: other, config_path: explicit)
        expect(config.config_path).to eq(explicit)
        config.set_ignored('Ziph', true)
        expect(YAML.safe_load(File.read(explicit))['ignore']).to eq(['Ziph'])
      ensure
        FileUtils.rm_rf(other)
      end
    end
  end
end
