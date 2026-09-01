# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'
require 'timeout'

# D-05/LOGS-05: when another process holds the build lock, BOTH blocking
# flock sites (Installer::Build#acquire_build_lock and
# Installer::Use#with_build_lock) announce 'Waiting for build lock…' to
# stdout BEFORE blocking -- exactly once, only when actually contended.
# The line rides Core::UI.info (bare puts -> $stdout, core/log.rb:14-16),
# so the Phase 12 tee captures it into the BLOCKED run's own JSONL while
# terminal users see the identical string (one string, two surfaces).
# The free-lock path is byte-identical to the pre-D-05 code: the free
# examples are regression pins that were green before D-05 landed and
# must stay green after.
module LockNoticeHelpers
  # Pinned copy (14-UI-SPEC 'Lock-wait line (D-05)'): capital W, one
  # ellipsis character, no trailing period. User-visible on two surfaces
  # (terminal + browser stream) and frozen once landed (BLD-02).
  NOTICE = 'Waiting for build lock…'

  # Included-module constants are not lexically reachable from example
  # blocks (Ruby resolves constants via the source cref, not the example
  # class ancestors) -- expose the pinned copy as a method too.
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

  # doctor_spec.rb:186-195 convention (via main_run_log_spec.rb:67-81):
  # manual $stdout/$stderr swap with begin/ensure restore, so the notice
  # under test lands in our StringIOs and never on the real terminal.
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

  # Thread-held flock contention: real OS-level flock on the real
  # Config#build_lock_path under a tmpdir project_dir, never a mock. The
  # holder thread takes LOCK_EX, signals once the lock is genuinely held,
  # then WAITS until the blocked run's notice is visible in the announce
  # buffer before releasing (plus a ~0.1s contended window) --
  # announce-BEFORE-block is therefore structural: an implementation that
  # announced only after acquiring would deadlock both sides into the
  # bounds and fail, not pass. Bounded waits everywhere (web_server_boot
  # thread/join discipline): a wedged holder fails the example, never the
  # suite.
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
        sleep 0.1 # the contended window the blocked run sits in flock(LOCK_EX)
      ensure
        f.flock(File::LOCK_UN)
        f.close
      end
    end
    held.pop
    # Sanity: the site under test contends THIS path (Config#build_lock_path
    # derives from project_dir, config.rb:110-112).
    expect(lock_currently_held?(path)).to be(true)
    Timeout.timeout(10, &block)
  ensure
    holder.kill unless holder.join(10)
  end

  def notice_count(text)
    text.scan(NOTICE).length
  end
end

RSpec.describe SPMCache::Installer::Build, 'lock-wait notice (D-05)' do
  include LockNoticeHelpers

  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  # Config#build_lock_path derives from project_dir (config.rb:110-112):
  # pointing project_dir at tmpdir makes THIS the real lock path.
  let(:lock_path) { File.join(tmpdir, '.spm-cache-build.lock') }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(graph_data: [{ 'module' => 'Alamofire', 'status' => 'missed' }])
  end

  before do
    FileUtils.mkdir_p(project_path)
    config = SPMCache::Core::Config.instance
    @original_project_dir = config.project_dir
    config.project_dir = tmpdir
    # Default-deny Sh guard (run_log_spec.rb:18-23 pattern): the lock
    # acquisition paths under test run before any toolchain call -- a real
    # shell-out here means the fence was mis-stubbed.
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
    # installer_build_spec.rb:20-32 hermetic idioms.
    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *_args|
      me = original.receiver
      me.instance_variable_set(:@cachemap, cachemap) if me.respond_to?(:cachemap)
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return({})
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target).and_return(nil)
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return('iphonesimulator')
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
  end

  after do
    SPMCache::Core::Config.instance.project_dir = @original_project_dir
    FileUtils.rm_rf(tmpdir)
  end

  it 'announces exactly once to stdout before blocking when the lock is contended' do
    elapsed = nil
    out, = with_swapped_streams do
      with_lock_held_until_notice(lock_path) do
        started = Time.now
        described_class.new(project: project_path, targets: []).perform_install
        elapsed = Time.now - started
      end
    end

    expect(notice_count(out)).to eq(1)
    expect(elapsed).to be >= 0.09 # genuinely deferred through the contended window
  end

  it 'emits no notice when the lock is free (byte-identical regression pin)' do
    elapsed = nil
    out, err = with_swapped_streams do
      started = Time.now
      described_class.new(project: project_path, targets: []).perform_install
      elapsed = Time.now - started
    end

    expect(out).not_to include(notice_text)
    expect(err).not_to include(notice_text)
    expect(elapsed).to be < 1.0 # completes immediately: nothing to wait for
  end

  it 'routes the notice to stdout (Core::UI.info), never stderr' do
    out, err = with_swapped_streams do
      with_lock_held_until_notice(lock_path) do
        described_class.new(project: project_path, targets: []).perform_install
      end
    end

    expect(out).to include(notice_text)
    expect(err).to be_empty
  end

  it 'triggers the announce from the LOCK_NB trylock RETURN VALUE -- raise-free, no error class in output' do
    # flock(LOCK_EX | LOCK_NB) returns false under contention and NEVER
    # raises (build_lock_spec.rb:41-45), so the probe is a plain
    # return-value check: no rescue-based skip path exists to take, and
    # no custom error class may ever surface in either stream.
    out, err = with_swapped_streams do
      with_lock_held_until_notice(lock_path) do
        described_class.new(project: project_path, targets: []).perform_install
      end
    end

    expect(out).to include(notice_text)
    expect(out + err).not_to match(/\[error\]|Error\b|Exception|EWOULDBLOCK|WouldBlock/i)
  end
end

RSpec.describe SPMCache::Installer::Use, 'lock-wait notice (D-05)' do
  include LockNoticeHelpers

  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  let(:lock_path) { File.join(tmpdir, '.spm-cache-build.lock') }

  before do
    FileUtils.mkdir_p(project_path)
    config = SPMCache::Core::Config.instance
    @original_project_dir = config.project_dir
    config.project_dir = tmpdir
    # Default-deny Sh guard (run_log_spec.rb:18-23 pattern).
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
    # build_lock_spec.rb:114-126 Use idioms.
    allow_any_instance_of(SPMCache::Installer).to receive(:verify_projects!)
    allow_any_instance_of(SPMCache::Installer).to receive(:detect_diff)
    allow_any_instance_of(SPMCache::Installer::Use).to receive(:fast_path?).and_return(false)
    allow_any_instance_of(SPMCache::Installer).to receive(:ensure_config_file)
    allow_any_instance_of(SPMCache::Installer).to receive(:sync_lockfile)
    allow_any_instance_of(SPMCache::Installer).to receive(:prepare_proxy)
    allow_any_instance_of(SPMCache::Installer).to receive(:recreate_dirs)
    allow_any_instance_of(SPMCache::Installer).to receive(:gen_supporting_files)
    allow_any_instance_of(SPMCache::Installer).to receive(:integrate_proxy_into_project)
    allow_any_instance_of(SPMCache::Installer).to receive(:gen_cachemap_viz)
  end

  after do
    SPMCache::Core::Config.instance.project_dir = @original_project_dir
    FileUtils.rm_rf(tmpdir)
  end

  it 'announces exactly once to stdout before blocking, then the deferred body runs' do
    body_ran = false
    allow_any_instance_of(SPMCache::Installer).to receive(:recreate_dirs) { body_ran = true }

    out, = with_swapped_streams do
      with_lock_held_until_notice(lock_path) do
        described_class.new(project: project_path).perform_install
      end
    end

    expect(notice_count(out)).to eq(1)
    expect(body_ran).to be(true) # the yield ran once the block lifted
  end

  it 'emits no notice when the lock is free (byte-identical regression pin)' do
    body_ran = false
    allow_any_instance_of(SPMCache::Installer).to receive(:recreate_dirs) { body_ran = true }

    out, err = with_swapped_streams do
      described_class.new(project: project_path).perform_install
    end

    expect(out).not_to include(notice_text)
    expect(err).not_to include(notice_text)
    expect(body_ran).to be(true)
  end
end
