# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/middleware_proxy'

DependencyDetection.defer do
  named :rails_middleware

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i >= 3
  end

  depends_on do
    !::NewRelic::Agent.config[:disable_middleware_instrumentation]
  end

  executes do
    ::NewRelic::Agent.logger.info("Installing Rails 3+ middleware instrumentation")
    module ActionDispatch
      class MiddlewareStack
        class Middleware
          def build_with_new_relic(app)
            result = build_without_new_relic(app)
            ::NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(result)
          end

          alias_method :build_without_new_relic, :build
          alias_method :build, :build_with_new_relic
        end
      end
    end
  end
end
