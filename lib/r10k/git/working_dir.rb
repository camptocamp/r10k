require 'r10k/logging'
require 'r10k/execution'
require 'r10k/git/command'
require 'r10k/git/cache'

module R10K
module Git
class WorkingDir
  # Implements sparse git repositories with shared objects
  #
  # Class instances are memoized based on the git remote path. This way if a
  # single git repository is instantiated multiple times, the object cache
  # will only be updated once.

  include R10K::Logging
  include R10K::Execution
  include R10K::Git::Command

  extend Forwardable

  # @!attribute [r] cache
  #   @return [R10K::Git::Cache]
  attr_reader :cache

  attr_reader :remote

  # Instantiates a new git synchro and optionally prepares for caching
  #
  # @param [String] remote A git remote URL
  def initialize(remote)
    @remote = remote

    @cache = R10K::Git::Cache.new(@remote)
  end

  # Synchronize the local git repository.
  #
  # @param [String] path The destination path for the files
  # @param [String] ref The git ref to instantiate at the destination path
  def sync(path, ref, options = {:update_cache => true})
    path = File.expand_path(path)
    @cache.sync if options[:update_cache]

    if self.cloned?(path)
      fetch(path)
    else
      clone(path)
    end
    reset(path, ref)
  end

  # Determine if repo has been cloned into a specific dir
  #
  # @param [String] dirname The directory to check
  #
  # @return [true, false] If the repo has already been cloned
  def cloned?(directory)
    File.directory?(File.join(directory, '.git'))
  end

  private

  # Perform a non-bare clone of a git repository.
  #
  # @param [String] path The directory to create the repo working directory
  def clone(path)
    # We do the clone against the target repo using the `--reference` flag so
    # that doing a normal `git pull` on a directory will work.
    git "clone --reference #{@cache.path} #{@remote} #{path}"
    git "remote add cache #{@cache.path}", :path => path
  end

  def fetch(path)
    # XXX This is crude but it'll ensure that the right remote is used for
    # the cache.
    git "remote set-url cache #{@cache.path}", :path => path
    git "fetch --prune cache", :path => path
  end

  # Reset a git repo with a working directory to a specific ref
  #
  # @param [String] path The path to the working directory of the git repo
  # @param [String] ref The git reference to reset to.
  def reset(path, ref)
    commit = resolve_commit(ref)

    begin
      git "reset --hard #{commit}", :path => path
    rescue R10K::ExecutionFailure => e
      logger.error "Unable to locate commit object #{commit} in git repo #{path}"
      raise
    end
  end

  # Resolve a ref to a commit hash
  #
  # @param [String] ref
  #
  # @return [String] The dereferenced hash of `ref`
  def resolve_commit(ref)
    commit = git "rev-parse #{ref}^{commit}", :git_dir => @cache.path
    commit.chomp
  rescue R10K::ExecutionFailure => e
    logger.error "Could not resolve ref #{ref.inspect} for git cache #{@cache.path}"
    raise
  end

end
end
end
