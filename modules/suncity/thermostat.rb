module Suncity; end

class Suncity::Thermostat
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 1235
    descriptive_name 'Thermostat'
    generic_name :Thermostat

    tokenize delimiter: "\x0D"

    def power(state)
        state = is_affirmative?(state)
        if state
            req = "ON"
        else
            req = "OFF"
        end
        logger.debug { "Sending #{req}" }
        req << 0x0D
        send(req, :delay => 5000, :timeout => 10000)
    end

    def received(data, deferrable, command)
        logger.debug { "received #{data}" }
    end
end
