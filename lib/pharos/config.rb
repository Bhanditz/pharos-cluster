# frozen_string_literal: true

require_relative 'types'
require_relative 'configuration/host'
require_relative 'configuration/api'
require_relative 'configuration/network'
require_relative 'configuration/etcd'
require_relative 'configuration/authentication'
require_relative 'configuration/cloud'
require_relative 'configuration/audit'
require_relative 'configuration/file_audit'
require_relative 'configuration/webhook_audit'
require_relative 'configuration/kube_proxy'
require_relative 'configuration/kubelet'
require_relative 'configuration/pod_security_policy'
require_relative 'configuration/telemetry'
require_relative 'configuration/admission_plugin'
require_relative 'configuration/container_runtime'

module Pharos
  class Config < Pharos::Configuration::Struct
    HOSTS_PER_DNS_REPLICA = 10

    using Pharos::CoreExt::DeepTransformKeys

    # @param raw_data [Hash]
    # @raise [Pharos::ConfigError]
    # @return [Pharos::Config]
    def self.load(raw_data)
      schema_data = Pharos::ConfigSchema.load(raw_data)

      config = new(schema_data)
      config.data = raw_data.freeze

      # inject api_endpoint & bastion to each host object
      config.hosts.each { |h| h.api_endpoint = config.api&.endpoint }

      config
    end

    attribute :hosts, Types::Coercible::Array.of(Pharos::Configuration::Host)
    attribute :network, Pharos::Configuration::Network
    attribute :kube_proxy, Pharos::Configuration::KubeProxy
    attribute :api, Pharos::Configuration::Api
    attribute :etcd, Pharos::Configuration::Etcd
    attribute :cloud, Pharos::Configuration::Cloud
    attribute :authentication, Pharos::Configuration::Authentication
    attribute :audit, Pharos::Configuration::Audit
    attribute :kubelet, Pharos::Configuration::Kubelet
    attribute :telemetry, Pharos::Configuration::Telemetry
    attribute :pod_security_policy, Pharos::Configuration::PodSecurityPolicy
    attribute :image_repository, Pharos::Types::String.default('registry.pharos.sh/kontenapharos')
    attribute :addon_paths, Pharos::Types::Array.default([])
    attribute :addons, Pharos::Types::Hash.default({})
    attribute :admission_plugins, Types::Coercible::Array.of(Pharos::Configuration::AdmissionPlugin)
    attribute :container_runtime, Pharos::Configuration::ContainerRuntime

    attr_accessor :data

    # @return [Integer]
    def dns_replicas
      return network.dns_replicas if network.dns_replicas
      return 1 if hosts.length == 1
      1 + (hosts.length / HOSTS_PER_DNS_REPLICA.to_f).ceil
    end

    # @return [Array<Pharos::Configuration::Node>]
    def master_hosts
      @master_hosts ||= hosts.select { |h| h.role == 'master' }
    end

    # @return [Pharos::Configuration::Node]
    def master_host
      sorted_master_hosts.first
    end

    def sorted_master_hosts
      master_hosts.sort_by(&:master_sort_score)
    end

    # @return [Array<Pharos::Configuration::Node>]
    def worker_hosts
      @worker_hosts ||= hosts.select { |h| h.role == 'worker' }
    end

    # @return [Array<Pharos::Configuration::Node>]
    def etcd_hosts
      return [] if etcd&.endpoints

      etcd_hosts = hosts.select { |h| h.role == 'etcd' }
      if etcd_hosts.empty?
        master_hosts
      else
        etcd_hosts
      end
    end

    def kube_client
      return @kube_client if @kube_client

      master = master_host

      kubeconfig_file = master.ssh.file("/etc/kubernetes/admin.conf")
      return nil unless kubeconfig_file.exist?

      kubeconfig = kubeconfig_file.read

      if master.bastion.nil?
        api_address = master.api_address
        api_port = 6443
      else
        api_address = 'localhost'
        api_port = master.ssh.gateway(master.api_address, 6443)
      end

      config = Pharos::Kube::Config.new(kubeconfig)
      config.update_server_address(api_address, api_port)

      @kube_client = Pharos::Kube.client(api_address, config.to_h, api_port)
    end

    def reset_kube_client
      @kube_client = nil
    end

    # @param key [Symbol]
    # @param value [Pharos::Configuration::Struct]
    # @raise [Pharos::ConfigError]
    def set(key, value)
      raise Pharos::Error, "Cannot override #{key}." if data[key.to_s]
      attributes[key] = value
    end

    # @return [String]
    def to_yaml
      YAML.dump(to_h.deep_stringify_keys)
    end
  end
end
