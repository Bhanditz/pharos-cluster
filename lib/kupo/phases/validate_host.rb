require_relative 'logging'

module Kupo::Phases
  class ValidateHost
    include Kupo::Phases::Logging

    # @param host [Kupo::Configuration::Host]
    def initialize(host)
      @host = host
    end

    def call
      logger.info(@host.address) { "Connecting to host via SSH ..." }
      ssh = Kupo::SSH::Client.for_host(@host)
      logger.info { "Gathering host facts ..." }
      gather_host_facts(ssh)
      logger.info { "Validating distro and version ..." }
      check_distro_version
      logger.info { "Validating host configuration ..." }
      check_cpu_arch
    end

    def check_distro_version
      unless @host.os_release.supported?
        raise Kupo::InvalidHostError, "Distro not supported: #{@host.os_release.name}"
      end
    end

    def check_cpu_arch
      unless @host.cpu_arch.supported?
        raise Kupo::InvalidHostError, "Cpu architecture not supported: #{@host.cpu_arch.id}"
      end
      if @host.cpu_arch.name != 'amd64' && @host.container_runtime == 'docker'
        raise Kupo::InvalidHostError, "Docker is only supported on amd64"
      end
    end

    # @param ssh [Kupo::SSH::Client]
    def gather_host_facts(ssh)
      @host.os_release = os_release(ssh)
      @host.cpu_arch = cpu_arch(ssh)
    end

    # @param ssh [Kupo::SSH::Client]
    # @return [Kupo::Configuration::OsRelease]
    def os_release(ssh)
      os_info = {}
      ssh.exec('cat /etc/os-release') do |_, data|
        data.split("\n").each do |line|
          match = line.match(/^(.+)=(.+)$/)
          os_info[match[1]] = match[2].gsub('"', '')
        end
      end
      Kupo::Configuration::OsRelease.new(
        id: os_info['ID'],
        id_like: os_info['ID_LIKE'],
        name: os_info['PRETTY_NAME'],
        version: os_info['VERSION_ID']
      )
    end

    # @param ssh [Kupo::SSH::Client]
    # @return [Kupo::Configuration::CpuArch]
    def cpu_arch(ssh)
      cpu = {}
      ssh.exec('lscpu') do |_, data|
        data.split("\n").each do |line|
          match = line.match(/^(.+):\s+(.+)$/)
          cpu[match[1]] = match[2]
        end
      end
      Kupo::Configuration::CpuArch.new(
        id: cpu['Architecture']
      )
    end
  end
end