# encoding: ASCII-8BIT

module Samsung; end
module Samsung::Displays; end

# Documentation: https://aca.im/driver_docs/Samsung/MDC+Protocol+2015+v13.7c.pdf

class Samsung::Displays::MdSeries
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder


    # Discovery Information
    tcp_port 1515
    descriptive_name 'Samsung MD, DM & QM Series LCD'
    generic_name :Display

# Markdown description
description <<-DESC
For DM displays configure the following options:

1. Network Standby = OFF (reduces the chance of a display crashing)
2. Set Auto Standby = OFF
3. Set Eco Solution, Auto Off = OFF

Hard Power off displays each night and wake on lan them in the morning.
DESC

    # Communication settings
    tokenize indicator: "\xAA", callback: :check_length
    default_settings display_id: 0


    #
    # Control system events
    def on_load
        on_update

        self[:volume_min] = 0
        self[:volume_max] = 100
        self[:power] = false

        # Meta data for inquiring interfaces
        self[:type] = :lcd
        self[:input_stable] = true
    end

    def on_unload
    end

    def on_update
        @id = setting(:display_id) || 0xFF
        do_device_config if self[:connected]
    end


    #
    # network events
    def connected
        do_device_config

        do_poll

        schedule.every('30s') do
            logger.debug "-- Polling Display"
            do_poll
        end
    end

    def disconnected
        #
        # Disconnected may be called without calling connected
        #   Hence the check if timer is nil here
        #
        @disconnecting = false
        self[:power] = false  # As we may need to use wake on lan
        schedule.clear
    end


    #
    # Command types
    COMMAND = {
        :hard_off => 0x11,      # Completely powers off
        :panel_mute => 0xF9,    # Screen blanking / visual mute
        :volume => 0x12,
        :brightness => 0x25,
        :input => 0x14,
        :mode => 0x18,
        :size => 0x19,
        :pip => 0x3C,           # picture in picture
        :auto_adjust => 0x3D,
        :wall_mode => 0x5C,     # Video wall mode
        :safety => 0x5D,
        :wall_on => 0x84,       # Video wall enabled
        :wall_user => 0x89,     # Video wall user control
        :speaker => 0x68,
        :net_standby => 0xB5,   # Keep NIC active in standby
        :eco_solution => 0xE6,  # Eco options (auto power off)
        :auto_power => 0x33,
        :screen_split => 0xB2    # Tri / quad split (larger panels only)
    }
    COMMAND.merge!(COMMAND.invert)

    # As true power off disconnects the server we only want to
    # power off the panel. This doesn't work in video walls
    # so if a nominal blank input is
    def power(power, broadcast = nil)
        if is_negatory?(power)
            # Blank the screen before turning off panel
            #if self[:power]
            #    blank = setting(:blank)
            #    unless blank.nil?
            #        switch_to blank
            #    end
            #end
            do_send(:panel_mute, 1)
        elsif !self[:connected]
            wake(broadcast)
        else
            do_send(:hard_off, 1)
            do_send(:panel_mute, 0)
        end
    end

    def hard_off
        do_send(:hard_off, 0).finally do
            # Actually takes awhile to shutdown!
            @disconnecting = true
            schedule.in('60s') do
                disconnect
            end
        end
    end

    def power?(options = {}, &block)
        options[:emit] = block unless block.nil?
        do_send(:panel_mute, [], options)
    end

    # Adds mute states compatible with projectors
    def mute(state = true)
        should_mute = is_affirmative?(state)
        power(!should_mute)
    end

    def unmute
        power(true)
    end


    INPUTS = {
        :vga => 0x14,       # pc in manual
        :dvi => 0x18,
        :dvi_video => 0x1F,
        :hdmi => 0x21,
        :hdmi_pc => 0x22,
        :hdmi2 => 0x23,
        :hdmi2_pc => 0x24,
        :hdmi3 => 0x31,
        :hdmi3_pc => 0x32,
        :hdmi4 => 0x33,
        :hdmi4_pc => 0x34,
        :display_port => 0x25,
        :dtv => 0x40,
        :media => 0x60,
        :widi => 0x61,
        :magic_info => 0x20,
        :whiteboard => 0x64
    }
    INPUTS.merge!(INPUTS.invert)

    def switch_to(input, options = {})
        input = input.to_sym if input.class == String
        self[:input_stable] = false
        self[:input_target] = input
        do_send(:input, INPUTS[input], options)
    end


    SCALE_MODE = {
        fill: 0x09,
        fit:  0x20
    }.tap { |x| x.merge!(x.invert).freeze }

    # Activite the internal compositor. Can either split 3 or 4 ways.
    def split(inputs = [:hdmi, :hdmi2, :hdmi3], layout: 0, scale: :fit, **options)
        main_source = inputs.shift

        data = [
            1,                  # enable
            0,                  # sound from screen section 1
            layout,             # layout mode (1..6)
            SCALE_MODE[scale],  # scaling for main source
            inputs.flat_map do |input|
                input = input.to_sym if input.is_a? String
                [INPUTS[input], SCALE_MODE[scale]]
            end
        ].flatten

        switch_to(main_source, options).then do
            do_send(:screen_split, data, options)
        end
    end

    def volume(vol, options = {})
        vol = in_range(vol.to_i, 100)
        do_send(:volume, vol, options)
    end

    def brightness(val, options = {})
        val = in_range(val.to_i, 100)
        do_send(:brightness, val, options)
    end


    #
    # Emulate mute
    def mute_audio(val = true)
        if is_affirmative? val
            if not self[:audio_mute]
                self[:audio_mute] = true
                self[:previous_volume] = self[:volume] || 50
                volume 0
            end
        else
            unmute_audio
        end
    end

    def unmute_audio
        if self[:audio_mute]
            self[:audio_mute] = false
            volume self[:previous_volume]
        end
    end

    Speaker_Modes = {
        internal: 0,
        external: 1
    }
    Speaker_Modes.merge!(Speaker_Modes.invert)
    def speaker_select(mode, options = {})
        do_send(:speaker, Speaker_Modes[mode.to_sym], options)
    end


    #
    # Maintain connection
    def do_poll
        req = do_send(:hard_off, [], priority: 0)
        req.then do
            unless self[:hard_off]
                power?(priority: 0) do
                    if self[:power] == On
                        do_send(:volume, [], priority: 0)
                        do_send(:input,  [], priority: 0)
                    end
                end
            end
        end

        # May have been powered off by the remote?
        # Samsung requires you disconnect after a hard power off
        # otherwise it will just ignore all requests
        req.catch { disconnect unless @disconnecting || !self[:connected] }
    end


    #
    # Enable power on (without WOL)
    def network_standby(enable, options = {})
        state = is_affirmative?(enable) ? 1 : 0
        do_send(:net_standby, state, options)
    end


    #
    # Eco auto power off timer
    def auto_off_timer(enable, options = {})
        state = is_affirmative?(enable) ? 1 : 0
        do_send(:eco_solution, [0x81, state], options)
    end


    #
    # Device auto power control (presumably signal based?)
    def auto_power(enable, options = {})
        state = is_affirmative?(enable) ? 1 : 0
        do_send(:auto_power, state, options)
    end


    protected


    DEVICE_SETTINGS = [
        :network_standby,
        :auto_off_timer,
        :auto_power
    ]
    #
    # Push any configured device settings
    def do_device_config
        logger.debug { "Syncronising device state with settings" }
        DEVICE_SETTINGS.each do |name|
            value = setting(name)
            __send__(name, value) unless value.nil?
        end
    end


    def wake(broadcast = nil)
        mac = setting(:mac_address)
        if mac
            # config is the database model representing this device
            wake_device(mac, broadcast)
            logger.debug {
                info = "Wake on Lan for MAC #{mac}"
                info << " directed to VLAN #{broadcast}" if broadcast
                info
            }
        else
            logger.debug { "No MAC address provided" }
        end
    end

    def received(response, resolve, command)
        logger.debug { "Samsung sent #{byte_to_hex(response)}" }

        data = str_to_array(response)

        len = data[2]
        status = data[3]
        command = data[4]
        value = len == 1 ? data[5] : data[5, len]

        case status
        when 0x41 # Ack
            case COMMAND[command]
            when :panel_mute
                self[:power] = value == 0
            when :volume
                self[:volume] = value
                if self[:audio_mute] && value > 0
                    self[:audio_mute] = false
                end
            when :brightness
                self[:brightness] = value
            when :input
                self[:input] = INPUTS[value]
                if not self[:input_stable]
                    if self[:input_target] == self[:input]
                        self[:input_stable] = true
                    else
                        switch_to(self[:input_target])
                    end
                end
            when :speaker
                self[:speaker] = Speaker_Modes[value]
            when :hard_off
                self[:hard_off] = value == 0
            when :screen_split
                self[:screen_split] = value.positive?
            end
            :success

        when 0x4e # Nak
            logger.debug "Samsung failed with: #{byte_to_hex(array_to_str(data))}"
            :failed  # Failed response

        else
            logger.debug "Samsung aborted with: #{byte_to_hex(array_to_str(data))}"
            :abort   # unknown result
        end
    end

    # Currently not used. We could check it if we like :)
    def check_checksum(byte_str)
        response = str_to_array(byte_str)
        check = 0
        response[0..-2].each do |byte|
            check = (check + byte) & 0xFF
        end
        response[-1] == check
    end

    # Called by the Abstract Tokenizer
    def check_length(byte_str)
        response = str_to_array(byte_str)
        return false if response.length <= 3

        len = response[2] + 4 # (data length + header and checksum)

        if response.length >= len
            return len
        else
            return false
        end
    end

    # Called by do_send to create a checksum
    def checksum(command)
        check = 0
        command.each do |byte|
            check = (check + byte) & 0xFF
        end
        command << check
    end

    def do_send(command, data = [], options = {})
        data = Array(data)

        if command.is_a?(Symbol)
            options[:name] = command if data.length > 0     # name unless status request
            command = COMMAND[command]
        end

        data = [command, @id, data.length] + data    # Build request (0xFF is screen id)
        checksum(data)                                # Add checksum
        data = [0xAA] + data                          # Add header
        send(array_to_str(data), options)
    end
end
