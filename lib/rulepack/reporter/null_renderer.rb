# frozen_string_literal: true

# Null renderer — for the json/yaml envelope formats. The Result payload
# renders once via Reporter; event narration must not mix into stdout.
# Subscribes to nothing and exists so the runner's subscribe/unsubscribe
# lifecycle stays uniform across formats. stderr diagnostics (Logging
# log_warn/log_error) still fire at the source.
module Rulepack
  module Reporter
    class NullRenderer
      def subscribe!; end

      def unsubscribe!; end
    end
  end
end
