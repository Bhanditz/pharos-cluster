# frozen_string_literal: true

require_relative 'debian'

module Pharos
  module Host
    class DebianStretch < Debian
      register_config 'debian', '9'

      CFSSL_VERSION = '1.2'
      DOCKER_VERSION = '18.06.2'

      register_component(
        name: 'cri-o', version: CRIO_VERSION, license: 'Apache License 2.0',
        enabled: proc { |c| c.hosts.any? { |h| h.container_runtime == 'cri-o' } }
      )

      register_component(
        name: 'cfssl', version: CFSSL_VERSION, license: 'MIT',
        enabled: proc { |c| !c.etcd&.endpoints }
      )

      register_component(
        name: 'docker-ce', version: DOCKER_VERSION, license: 'Apache License 2.0',
        enabled: proc { |c| c.hosts.any? { |h| h.container_runtime == 'docker' } }
      )

      def configure_repos
        exec_script("repos/pharos_stretch.sh")
        exec_script('repos/update.sh')
      end

      def configure_container_runtime
        if docker?
          exec_script(
            'configure-docker.sh',
            DOCKER_PACKAGE: 'docker-ce',
            DOCKER_VERSION: DOCKER_VERSION,
            INSECURE_REGISTRIES: insecure_registries
          )
        elsif custom_docker?
          exec_script(
            'configure-docker.sh',
            INSECURE_REGISTRIES: insecure_registries
          )
        elsif crio?
          exec_script(
            'configure-cri-o.sh',
            CRIO_VERSION: Pharos::CRIO_VERSION,
            CRIO_STREAM_ADDRESS: '127.0.0.1',
            CPU_ARCH: host.cpu_arch.name,
            IMAGE_REPO: config.image_repository,
            INSECURE_REGISTRIES: insecure_registries
          )
        else
          raise Pharos::Error, "Unknown container runtime: #{host.container_runtime}"
        end
      end

      def configure_container_runtime_safe?
        return true if custom_docker?

        if docker?
          result = ssh.exec("dpkg-query --show docker-ce")
          return true if result.error? # docker not installed
          return true if result.stdout.split("\t")[1].to_s.start_with?(DOCKER_VERSION)
        elsif crio?
          result = ssh.exec("dpkg-query --show cri-o")
          return true if result.error? # cri-o not installed
          return true if result.stdout.split("\t")[1].to_s.start_with?(Pharos::CRIO_VERSION)
        end

        false
      end

      def reset
        exec_script(
          "reset.sh",
          CRIO_VERSION: CRIO_VERSION
        )
      end
    end
  end
end
