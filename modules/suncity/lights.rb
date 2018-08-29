module Suncity; end

class Suncity::Lights
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 1234
    descriptive_name 'Lights'
    generic_name :Lights

    tokenize delimiter: "\x0D"

    def light_level(area, state = nil, brightness = nil, options = {})
        if !state.nil?
            state = is_affirmative?(state)
            if state
                req = "CH4@ON"
            else
                req = "CH4@OFF"
            end
            for i in 4..9
            end
        elsif !brightness.nil?
            brightness = in_range(brightness, 100, 0)
            req = "CH1@#{brightness.to_s}"
            for i in 1..3
            end
        end
        logger.debug { "Sending #{req}" }
        req << 0x0D
        send(req, options)
    end

    def received(data, deferrable, command)
        logger.debug { "received #{data}" }
    end
end
