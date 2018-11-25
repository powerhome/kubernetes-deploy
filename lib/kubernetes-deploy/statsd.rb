# frozen_string_literal: true
require 'statsd-instrument'
require 'logger'

module KubernetesDeploy
  class StatsD
    def self.duration(start_time)
      (Time.now.utc - start_time).round(1)
    end

    def self.build
      ::StatsD.default_sample_rate = 1.0
      ::StatsD.prefix = "KubernetesDeploy"

      if ENV['STATSD_DEV'].present?
        ::StatsD.backend = ::StatsD::Instrument::Backends::LoggerBackend.new(Logger.new($stderr))
      elsif ENV['STATSD_ADDR'].present?
        statsd_impl = ENV['STATSD_IMPLEMENTATION'].present? ? ENV['STATSD_IMPLEMENTATION'] : "datadog"
        ::StatsD.backend = ::StatsD::Instrument::Backends::UDPBackend.new(ENV['STATSD_ADDR'], statsd_impl)
      else
        ::StatsD.backend = ::StatsD::Instrument::Backends::NullBackend.new
      end
      ::StatsD.backend
    end

    module MeasureMethods
      def measure_method(method_name, metric = nil)
        unless method_defined?(method_name) || private_method_defined?(method_name)
          raise NotImplementedError, "Cannot instrument undefined method #{method_name}"
        end

        unless const_defined?("InstrumentationProxy")
          const_set("InstrumentationProxy", Module.new)
          should_prepend = true
        end
        instrumentation_proxy = const_get("InstrumentationProxy")
        metric ||= "#{method_name}.duration"

        instrumentation_proxy.send(:define_method, method_name) do |*args, &block|
          start_time = Time.now.utc
          result = super(*args, &block)
          dynamic_tags = send(:statsd_tags) if respond_to?(:statsd_tags, true)
          ::StatsD.distribution(metric, KubernetesDeploy::StatsD.duration(start_time), tags: dynamic_tags)
          result
        end

        prepend(instrumentation_proxy) if should_prepend
      end
    end
  end
end
