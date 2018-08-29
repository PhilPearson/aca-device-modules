require 'modbus'

module JohnsonControls; end

class JohnsonControls::Thermostat
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    tcp_port 3689
    descriptive_name 'Johnson Controls T8600 Thermostat'
    generic_name :AirCondition

    def on_load
        @modbus = Modbus.new
    end

    def on_update
        @use_serial = setting(:over_serial) || false
    end

    def power?
        request = @modbus.read_holding_registers(40003)
        send_req(request, :name => :power)
    end

    def power(state)
        target = is_affirmative?(state)
        self[:power_target] = target

        # Execute command
        logger.debug { "Target = #{target} and self[:power] = #{self[:power]}" }
        if target == On && self[:power] != On
            request = @modbus.write_holding_registers(40003, 0)
        elsif target == Off && self[:power] != Off
            request = @modbus.write_holding_registers(40003, 1)
        end
        send_req(request, :name => :power)
    end

    def temp?
        request = @modbus.read_input_registers(30001)
        send_req(request, :name => :temp)
    end

    MODES = {
        :cool => 1,
        :heat => 2,
        :fresh_air => 3
    }
    MODES.merge!(MODES.invert)
    def mode?
        request = @modbus.read_holding_registers(40004)
        send_req(request, :name => :mode)
    end

    def mode(state)
        state = state.to_sym if state.class == String

        request = @modbus.write_holding_registers(40004, MODES[state])
        send_req(request, :name => :mode)
    end

    def point?
        request = @modbus.read_holding_registers(40005)
        send_req(request, :name => :point)
    end

    def point(position)
        position = in_range(position, 300, 160)

        request = @modbus.write_holding_registers(40005, MODES[state])
        send_req(request, :name => :point)
    end


    SPEED = {
        :high => 0,
        :mid => 1,
        :low => 2,
        :auto => 3
    }
    SPEED.merge!(SPEED.invert)
    def fanspeed?
        request = @modbus.read_holding_registers(40006)
        send_req(request, :name => :fanspeed)
    end

    def fanspeed(speed)
        request = @modbus.write_holding_registers(40006, SPEED[state])
        send_req(request, :name => :fanspeed)
    end

    def send_req(req, options = {})
        byte_string = req.to_binary_s serial: @use_serial
        send(byte_string, options)
    end

    def received(data, deferrable, command)
        logger.debug { "Received #{data}" }
=begin
        @modbus.read(data, serial: @use_serial) do |adu|
            # Response PDU returned
            if adu.exception?
                # Get error message
                puts adu.value
                # Error code
                puts adu.pdu.exception_code
            else
                case adu.function_name
                when :read_coils
                    # or values
                    puts adu.value # => [true, false, true, false, false, false, false, false]
                when :read_input_registers
                    # Grab the 16 bit values
                    puts adu.value # => [1234, 8822]
                end
            end
        end
=end
        :success
    end
end
