# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'
require 'timeout'
require 'fileutils'

# BLD-04/CP4: Installer::Rollback#perform_install joins the SAME build flock
# Installer::Build and Installer::Use already contend on -- a rollback can no
# longer race a build's writes to the sandbox out from under it. D-07: the
# fix lives in the installer, so every caller (terminal, and 15-01's
# UI-spawned subprocess) inherits it without the web layer re-implementing
# rollback. Follows installer_lock_notice_spec.rb's conventions verbatim:
# thread-held real-OS flock for contention, manual $stdout/$stderr swap,
# byte-exact pinned copy.
module RollbackLockHelpers
  # Pinned copy (14-UI-SPEC 'Lock-wait line (D-05)'): capital W, one
  # ellipsis character, no trailing period. Now a THIRD site shares this
  # literal (build.rb, use.rb, rollback.rb) -- frozen across terminal and
  # browser (BLD-02).
  NOTICE = 'Waiting for build lock…'

  def notice_text
    NOTICE
  end

  # build_lock_spec.rb:77-83 idiom: probe without stealing the lock.
  def lock_currently_held?(path)
    probe = File.open(path, File::CREAT | File::RDWR)
    held = probe.flock(File::LOCK_EX | File::LOCK_NB) == false
    probe.flock(File::LOCK_UN) unless held
    probe.close
    held
  end

  # installer_lock_notice_spec.rb:41-58 convention: manual $stdout/$stderr
  # swap with begin/ensure restore.
  def with_swapped_streams
    out = StringIO.new
    err = StringIO.new
    old_out = $stdout
    old_err = $stderr
    $stdout = out
    $stderr = err
    begin
      yield
    ensure
      $stdout = old_out
      $stderr = old_err
    end
    [out.string, err.string]
  end

  # installer_lock_notice_spec.rb:60-101: thread-held real-OS flock on the
  # real Config#build_lock_path under a tmpdir project. The holder signals
  # once it genuinely owns the lock, then waits (bounded) until the
  # announce is visible before releasing, so announce-BEFORE-block is
  # structural, never a race in the test itself.
  def with_lock_held_until_notice(path, announce_visible_in: nil, &block)
    FileUtils.mkdir_p(File.dirname(path))
    held = Queue.new
    holder = Thread.new do
      f = File.open(path, File::CREAT | File::RDWR)
      begin
        f.flock(File::LOCK_EX)
        held << true
        deadline = Time.now + 2
        until if announce_visible_in
                announce_visible_in.string.include?(NOTICE)
              else
                $stdout.respond_to?(:string) && $stdout.string.include?(NOTICE)
              end
          break if Time.now > deadline

          sleep 0.005
        end
        sleep 0.1 # the contended window the blocked call sits in flock(LOCK_EX)
      ensure
        f.flock(File::LOCK_UN)
        f.close
      end
    end
    held.pop
    expect(lock_currently_held?(path)).to be(true)
    Timeout.timeout(10, &block)
  ensure
    holder.kill unless holder.join(10)
  end
end

RSpec.describe SPMCache::Installer::Rollback, 'build-lock acquisition (BLD-04/CP4)' do
  include RollbackLockHelpers

  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  # Config#build_lock_path derives from project_dir (config.rb:110-112):
  # pointing project_dir at tmpdir makes THIS the real lock path.
  let(:lock_path) { File.join(tmpdir, '.spm-cache-build.lock') }
  let(:sandbox_dir) { File.join(tmpdir, '.spm-cache') }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(sandbox_dir)
    config = SPMCache::Core::Config.instance
    @original_project_dir = config.project_dir
    config.project_dir = tmpdir
    # Default-deny Sh guard (run_log_spec.rb:18-23 pattern): rollback's
    # critical section is a print plus an rm_rf -- a real shell-out here
    # means the fence was mis-stubbed.
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after do
    SPMCache::Core::Config.instance.project_dir = @original_project_dir
    FileUtils.rm_rf(tmpdir)
  end

  def rollback
    described_class.new(project: project_path)
  end

  it 'holds the lock BEFORE touching the project: the sandbox survives while a holder owns the flock, and is gone once it releases' do
    FileUtils.mkdir_p(sandbox_dir) unless File.directory?(sandbox_dir)

    with_swapped_streams do
      with_lock_held_until_notice(lock_path) do
        # The caller thread announces (prints NOTICE) before entering the
        # blocking flock -- polling for that text is a deterministic signal
        # that it has NOT yet acquired the lock and therefore has not yet
        # touched the project, without relying on Thread#status.
        caller_thread = Thread.new { rollback.perform_install }
        Timeout.timeout(5) { sleep 0.005 until $stdout.string.include?(notice_text) }
        expect(File.directory?(sandbox_dir)).to be(true)
        caller_thread.join(10)
      end
    end

    expect(File.directory?(sandbox_dir)).to be(false)
  end

  it 'genuinely holds the flock across the critical section: a non-blocking probe fails during, succeeds after' do
    with_swapped_streams do
      with_lock_held_until_notice(lock_path) do
        caller_thread = Thread.new { rollback.perform_install }
        Timeout.timeout(5) { sleep 0.005 until $stdout.string.include?(notice_text) }
        expect(lock_currently_held?(lock_path)).to be(true)
        caller_thread.join(10)
      end
    end

    expect(lock_currently_held?(lock_path)).to be(false)
  end

  it 'releases on raise (Pitfall 6): the raise propagates unchanged and a subsequent acquire succeeds' do
    allow_any_instance_of(described_class).to receive(:remove_proxy).and_raise(StandardError, 'boom')

    expect { rollback.perform_install }.to raise_error(StandardError, 'boom')
    # Genuinely proves release-after-raise (not vacuously true absent any
    # acquisition at all): the lock file must exist -- it is only ever
    # created by acquire_build_lock's File.open(CREAT | RDWR) -- AND a
    # fresh non-blocking probe must succeed, i.e. nothing is wedged.
    expect(File.exist?(lock_path)).to be(true)
    expect(lock_currently_held?(lock_path)).to be(false)
  end

  it 'announces exactly once, byte-identical to the build/use sites, when contended' do
    out, = with_swapped_streams do
      with_lock_held_until_notice(lock_path) do
        rollback.perform_install
      end
    end

    expect(out.scan(notice_text).length).to eq(1)
  end

  it 'emits no notice on the free path (byte-identical to today)' do
    out, err = with_swapped_streams do
      rollback.perform_install
    end

    expect(out).not_to include(notice_text)
    expect(err).not_to include(notice_text)
    expect(out).to eq("Restoring original package references...\nRemoved spm-cache sandbox\n")
  end

  it 'routes the notice to stdout (Core::UI.info), never stderr' do
    out, err = with_swapped_streams do
      with_lock_held_until_notice(lock_path) do
        rollback.perform_install
      end
    end

    expect(out).to include(notice_text)
    expect(err).to be_empty
  end
end
