module Suncity; end

class Suncity::Drapes
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 1236
    descriptive_name 'Drapes'
    generic_name :Drapes

    tokenize delimiter: "\x0D"

    def curtain_level(state, options = {})
        state = is_affirmative?(state)
        if state
            req = "UP"
        else
            req = "DOWN"
        end
        logger.debug { "Sending #{req}" }
        req << 0x0D
        send(req, :delay => 5000, :timeout => 10000)
    end

    def received(data, deferrable, command)
        logger.debug { "received #{data}" }

        # DrapeUP
        # DrapeDOWN
    end
end
