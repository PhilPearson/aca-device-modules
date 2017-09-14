# encoding: ASCII-8BIT

module X3m; end
module X3m::Displays; end

class X3m::Displays::WallDisplay
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    tcp_port 4999  # control assumed via Global Cache
    descriptive_name '3M Wall Display'
    generic_name :Display

    description <<-DESC
        Display control is via RS-232 only. Ensure IP -> RS-232 converter has
        been configured to provide comms at 9600,N,8,1.
    DESC

    tokenize delimiter: "\r"

    def on_load
        on_update

        self[:power] = false

        # Meta data for inquiring interfaces
        self[:type] = :lcd
    end

    def on_unload
    end

    def on_update
        self[:volume_min] = setting(:volume_min) || 0
        self[:volume_max] = setting(:volume_max) || 100
    end

    def connected
        do_poll

        schedule.every '30s', method(:do_poll)
    end

    def disconnected
        schedule.clear
    end

    def do_poll

    end

    def power(state)
        logger.debug "Setting power #{state}"

        if is_affirmative? state
            set :power, 1
        else
            set :power, 0
        end
    end

    def volume(level)

    end

    def mute(state = true)

    end

    def unmute

    end

    def switch_to(input)

    end

    def mute_audio(state = true)

    end

    def unmute_audio

    end

    protected

    def set(command, param, opts = {}, &block)
        packet = Protocol.build_packet(command, param)

        opts[:emit] = block if block_given?
        opts[:name] ||= command

        send packet, opts
    end

    def received(response, resolve, command)

    end
end

module X3m::Displays::WallDisplay::Protocol
    module_function

    MARKER = {
        :SOH => 0x01,
        :STX => 0x02,
        :ETX => 0x03,
        :delimiter => 0x0d,
        :reserved => 0x30
    }

    MONITOR_ID = {
        :all => 0x2a
    }.merge Hash[(1..9).zip(0x41..0x49)]

    MESSAGE_SENDER = {
        :pc => 0x30
    }

    MESSAGE_TYPE = {
        :set_parameter_command => 0x45,
        :set_parameter_reply => 0x46
    }

    COMMAND = {
        :brightness => 0x0110,
        :contrast => 0x0112,
        :power => 0x0003
    }

    # Build a 'set_parameter_command' packet ready for transmission to the
    # device(s). Command should be one of the symbols from the COMMAND hash.
    def build_packet(command, param, monitor_id: :all)
        message = [
            MARKER[:STX],
            *Util.byte_arr(COMMAND[command], length: 4),
            *Util.byte_arr(param, length: 4),
            MARKER[:ETX]
        ]

        header = [
            MARKER[:SOH],
            MARKER[:reserved],
            MONITOR_ID[monitor_id],
            MESSAGE_SENDER[:pc],
            MESSAGE_TYPE[:set_parameter_command],
            *Util.byte_arr(message.length, length: 2)
        ]

        # XOR of all bytes in header and message for checksum
        bcc = (header + message).reduce(:^)

        header + message << bcc << MARKER[:delimiter]
    end
end

module X3m::Displays::WallDisplay::Protocol::Util
    module_function

    # Convert an integral value into a string with its hexadecimal
    # representation.
    #
    # as_hex(10, width: 2)
    #  => "0A"
    def as_hex(value, width:)
        value
            .to_s(16)
            .rjust(width, '0')
            .upcase
    end

    # Convert an integral value to a byte array, with each element containing
    # the ASCII character code that represents the original value at that
    # offset (big-endian).
    #
    # byte_arr(10, width: 2)
    #  => [48, 65]
    def byte_arr(value, length:)
        as_hex(value, width: length)
            .bytes
    end

    # Expand a hashmap to provide inverted k/v pairs for bi-directional lookup
    def two_way_hash(hash)
        hash
            .merge(hash.invert)
            .freeze
    end
end