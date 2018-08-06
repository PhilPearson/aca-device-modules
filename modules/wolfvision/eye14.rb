module Wolfvision; end

# Documentation: https://www.wolfvision.com/wolf/protocol_command_wolfvision/protocol/commands_eye-14.pdf

class Wolfvision::Eye14
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 50915 # Need to go through an RS232 gatway
    descriptive_name 'WolfVision EYE-14'
    generic_name :Camera

    # Communication settings
    tokenize indicator: /\x00|\x01|/, callback: :check_length
    delay between_sends: 150

    def on_load
        self[:zoom_max] = self[:iris_max] = 620
        self[:zoom_min] = self[:iris_min] = 0
        on_update
    end

    def on_update
        logger.debug { "updated" }
    end

    def on_unload
    end

    def connected
=begin
        schedule.every('60s') do
            logger.debug "-- Polling Sony Camera"
            power? do
                if self[:power] == On
                    zoom?
                    autofocus?
                end
            end
        end
=end
    end

    def disconnected
        # Disconnected will be called before connect if initial connect fails
        schedule.clear
    end

    def power(state)
        target = is_affirmative?(state)

        # Execute command
        logger.debug { "Target = #{target} and self[:power] = #{self[:power]}" }
        if target == On && self[:power] == Off
            send_cmd("\x30\x01\x01", name: :power, delay: 15000)
        elsif target == Off && self[:power] == On
            send_cmd("\x30\x01\x00", name: :power, delay: 15000)
        end

        # ensure the command ran successfully
        self[:power_target] = target
        power?
        set_autofocus
    end

    # uses only optical zoom
    def zoom(position)
        val = in_range(position, self[:zoom_max], self[:zoom_min])
                val = sprintf("%04X", val)
                logger.debug { "position in decimal is #{position} and hex is #{val}" }
        send_cmd("\x20\x02#{hex_to_byte(val)}")
        self[:zoom] = position
    end

    def zoom?
        send_inq("\x20\x00", priority: 0, inq: :zoom)
    end

    # set autofocus to on
    def set_autofocus
        send_cmd("\x31\x01\01", name: :set_autofocus)
    end

    def autofocus?
        send_inq("\x31\00", priority: 0, inq: :autofocus)
    end

    def iris(position)
        val = in_range(position, self[:iris_max], self[:iris_min])
                val = sprintf("%04X", val)
                logger.debug { "position in decimal is #{position} and hex is #{val}" }
        send_cmd("\x22\x02#{hex_to_byte(val)}")
        self[:iris] = position
    end

    def iris?
        send_inq("\x22\x00", priority: 0, inq: :iris)
    end

    def power?(options = {}, &block)
        options[:emit] = block if block_given?
        options[:inq] = :power
        send_inq("\x30\x00", options)
    end

    def send_cmd(cmd, options = {})
        req = "\x01#{cmd}"
        logger.debug { "tell -- 0x#{byte_to_hex(req)} -- #{options[:name]}" }
        send(req, options)
    end

    def send_inq(inq, options = {})
        req = "\x00#{inq}"
        logger.debug { "ask -- 0x#{byte_to_hex(req)} -- #{options[:inq]}" }
        send(req, options)
    end

    def received(data, deferrable, command)
        logger.debug { "Received 0x#{byte_to_hex(data)}" }

        return :success if command && command[:inq].nil?

        bytes = str_to_array(data)
        case command[:inq]
        when :power
            # -1 index for array refers to the last element in Ruby
            self[:power] = bytes[-1] == 1

            # if power target is not nil and current power
            if !self[:power_target].nil? && self[:power_target] != self[:power]
                if self[:power_target] != self[:power]
                     power(self[:power_target])
                end
            end
        when :zoom
            hex = byte_to_hex(data[-2..-1])
            self[:zoom] = hex.to_i(16)
            logger.debug { "zoom, hex is #{hex} = #{hex.to_i(16)} in decimal" }
            # TODO
        when :autofocus
                self[:autofocus] = bytes[-1] == 1
        when :iris
                hex = byte_to_hex(data[-2..-1])
                self[:iris] = hex.to_i
                logger.debug{ "iris, hex is #{hex} = #{hex.to_i(16)} in decimal" }
        end

        return :success
    end

    def check_length(byte_str)
                response = str_to_array(byte_str)
                logger.debug { "#{response} length = #{response.length}" }

                return false if response.length <= 2 # header is 2 bytes

                len = response[1] + 2 # (data length + header)

                if response.length >= len
                        return len
                else
                        return false
                end
        end

end
