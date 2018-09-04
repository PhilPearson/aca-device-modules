# encoding: ASCII-8BIT
# frozen_string_literal: true

module Foxtel; end

class Foxtel::Iq2
    include ::Orchestrator::Constants

    # Discovery Information
    descriptive_name 'FoxtelSet Top Box IQ2'
    generic_name :Receiver
    implements :logic

    def on_load
        on_update
    end

    def on_update
        self[:ir_driver] = @ir_driver = setting(:ir_driver)&.to_sym || :DigitalIO
        self[:ir_index] = @ir_index = setting(:ir_index) || 1
    end

    # Here for compatibility
    def power(state = true, **options)
        logger.debug 'toggling power'
        do_send('1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,28,6,10,6,3237')
        true
    end

    DIRECTIONS = {
        left: '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,16,6,16,6,22,6,22,6,3218',
        right: '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,16,6,16,6,22,6,28,6,3212',
        up: '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,16,6,16,6,22,6,10,6,3230',
        down: '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,16,6,16,6,22,6,16,6,322'
    }
    def cursor(direction, **options)
        logger.debug { "cursor #{direction}" }
        val = DIRECTIONS[direction.to_sym]
        raise "invalid direction #{direction}" unless val
        do_send(val)
    end

    def num(number, **options)
        val = case number.to_i
        when 0 then '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,10,6,10,6,325'
        when 1 then '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,10,6,16,6,324'
        when 2 then '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,10,6,22,6,324'
        when 3 then '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,10,6,28,6,323'
        when 4 then '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,16,6,10,6,324'
        when 5 then '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,16,6,16,6,324'
        when 6 then '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,16,6,22,6,323'
        when 7 then '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,16,6,28,6,323'
        when 8 then '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,22,6,10,6,324'
        when 9 then '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,10,6,22,6,16,6,323'
        else raise ArgumentError, 'num may only be used for single digits, use #channel otherwise'
        end
        do_send(val)
    end

    # Make compatible with IPTV systems
    def channel(number)
        logger.debug { "switching to channel #{number}" }
        number.to_s.each_char do |char|
            num(char)
        end
    end

    COMMANDS = {
        menu:        '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,22,6,10,6,28,6,22,6,3212',
        setup:       '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,16,6,16,6,16,6,10,6,3237',
        enter:       '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,16,6,16,6,28,6,10,6,3224',
        channel_up:  '1,36000,1,1,15,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,22,6,10,6,10,6,3231',
        channel_down:'1,36000,1,1,15,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,10,6,22,6,10,6,16,6,3225',
        guide:       '1,37000,1,1,16,10,6,10,6,22,6,10,6,16,6,22,6,22,6,10,6,10,6,10,6,22,6,16,6,22,6,28,6,10,6,28,6,10,6,3218'
    }

    # Automatically creates a callable function for each command
    COMMANDS.each do |command, value|
        define_method command do |**options|
            logger.debug { "sending #{command}" }
            do_send(value)
        end
    end

    protected

    def do_send(cmd)
        system[@ir_driver].ir(@ir_index, cmd)
    end
end
