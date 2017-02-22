module Aca; end

::Orchestrator::DependencyManager.load('Aca::Joiner', :logic)

class Aca::MeetingRoom < Aca::Joiner
    descriptive_name 'ACA Meeting Room Logic'
    generic_name :System
    default_settings joiner_driver: :System
    implements :logic


    def on_load
        @waiting_for = {}

        # Call the Joiner load function
        super
    end

    def on_update
        begin
            self[:name] = system.name
            self[:help_msg] = setting(:help_msg)
            self[:analytics] = setting(:analytics)

            # Get any default settings
            @defaults = setting(:defaults) || {}

            # Pod sharing settings
            @always_share = !!setting(:always_share)
            self[:Presenter_hide] = self[:Presenter_hide] ? !@always_share : false
            self[:is_slave_system] = setting(:is_slave_system) || false

            # Grab the input list
            @input_tab_mapping = {}             # Used in POD sharing code
            self[:inputs] = setting(:inputs)
            my_inputs = []
            self[:inputs].each do |input|
                self[input] = setting(input)
                (self[input] || []).each do |source|
                    my_inputs << source
                    @input_tab_mapping[source.to_sym] = input
                end
            end
            self[:local_inputs] = my_inputs

            # Grab any video wall details
            # {Display_1: {module: VidWall, input: display_port} }
            @vidwalls = setting(:vidwalls) || {}

            # We don't want to break things on update if inputs define audio settings
            # and there is a presentation currently
            @original_outputs = setting(:outputs)
            self[:outputs] = ActiveSupport::HashWithIndifferentAccess.new.deep_merge(@original_outputs)

            # Grab the list of inputs and outputs
            self[:sources] = setting(:sources)
            modes = setting(:modes)
            if modes
                @modes = modes
                self[:modes] = setting(:ignore_modes) ? nil : @modes.keys
                switch_mode(self[:current_mode]) if self[:current_mode]
            else
                @modes = nil
                self[:modes] = nil
                self[:current_mode] = nil
            end

            self[:mics] = setting(:mics)
            @sharing_output = self[:outputs].keys.first

            # Grab lighting presets
            self[:lights] = setting(:lights)
            @light_mapping = {}
            if self[:lights]
                if self[:lights][:levels]
                    self[:lights][:levels].each do |level|
                        @light_mapping[level[:name]] = level[:trigger]
                        @light_mapping[level[:trigger]] = level[:name]
                    end
                end

                @light_default = self[:lights][:default]
                @light_present = self[:lights][:present]
                @light_shutdown = self[:lights][:shutdown]
                @light_group = setting(:lighting_group)
            end

            # Check for min / max volumes
            if @original_min != setting(:vol_min)
                @original_min = setting(:vol_min)
                self[:vol_min] = @original_min
            end

            if @original_max != setting(:vol_max)
                @original_max = setting(:vol_max)
                self[:vol_max] = @original_max
            end
            

            # Get the list of apps and channels
            @apps = setting(:apps)
            @channels = setting(:channels)
            @cameras = setting(:cameras)
            @no_cam_on_boot = setting(:no_cam_on_boot)
            self[:has_preview] = setting(:has_preview)
            self[:pc_control] = system.exists?(:Computer)
            self[:apps] = @apps.keys if @apps
            self[:channels] = @channels.keys if @channels
            self[:cameras] = @cameras.keys if @cameras

            # Example definition:
=begin
            "blinds": [{
                "title": "Glass",
                "module": "DigitalIO_1",
                "feedback": "relay1",
                "closed_value": true,
                "open_value": false,
                "func": "relay",
                "args": [1] # NOTE:: The open or closed value will be appended to the args list
            }]
=end
            self[:blinds] = setting(:blinds)

        rescue => e
            logger.print_error(e, 'bad system logic configuration')
        end

        # Update the Schedules
        begin
            # Shutdown schedule
            # Every night at 11:30pm shutdown the systems if they are on
            @shutdown_timer.cancel if @shutdown_timer
            @shutdown_timer = schedule.cron(setting(:shutdown_time) || '30 23 * * *') do
                shutdown
            end

            # Startup schedule
            @warmup_timer.cancel if @warmup_timer
            time = setting(:warmup_time)
            if time
                @warmup_timer = schedule.cron(time) do
                    warm_up_displays
                end
            end

            # Poweroff schedule
            @hardoff_timer.cancel if @hardoff_timer
            time = setting(:hardoff_time)
            if time
                @hardoff_timer = schedule.cron(time) do
                    hard_off_displays
                end
            end
        rescue => e
            logger.print_error(e, 'bad cron schedule configuration')
        end

        # Call the Joiner on_update function
        super
    end


    #
    # SOURCE SWITCHING
    #

    # The current tab being viewed
    def tab(tabid)
        self[:tab] = tabid.to_sym
        self[:selected_tab] = tabid.to_s
    end

    def preview(source)
        if self[:has_preview]
            disp_source = self[:sources][source.to_sym]
            preview_input = disp_source[:preview] || disp_source[:input]

            system[:Switcher].switch({preview_input => self[:has_preview]})
        end
    end

    def join(*ids)
        promise = super(*ids)

        promise.then do
            # Remote enable the presenter tab and switch to it
            perform_action(mod: :System, func: :enable_sharing, args: [true])

            # Present sharing output on other displays if already presenting
            output1 = self[:outputs].keys.first
            current = self[output1]
            if current && current[:source] != :none && current[:source] != :sharing_input
                perform_action(mod: :System, func: :do_share, args: [true, current[:source]], skipMe: true).then do
                    # defaults = {
                        # sharing_routes: {input: [outputs]}
                        # on_sharing_preset: 'preset_name'
                    # }
                    system[:Mixer].trigger(@defaults[:on_sharing_trigger]) if @defaults[:on_sharing_trigger]
                    system[:Switcher].switch(@defaults[:sharing_routes]) if @defaults[:sharing_routes]
                end
            end
        end

        promise
    end

    def unjoin
        perform_action(mod: :System, func: :enable_sharing, args: [false]).then do
            super.then do
                system[:Mixer].trigger(@defaults[:off_sharing_trigger]) if @defaults[:off_sharing_trigger]
            end
        end
    end

    def present(source, display)
        present_actual(source, display)

        # Switch Joined rooms to the sharing input (use skipme param)
        perform_action(mod: :System, func: :do_share, args: [true, source.to_sym], skipMe: true).then do
            system[:Switcher].switch(@defaults[:sharing_routes]) if @defaults[:sharing_routes]
        end
    end

    def present_actual(source, display)
        powerup if self[:state] != :online

        display = (display || :all_displays).to_sym
        source = source.to_sym

        if display == :all_displays
            self[:outputs].each_key do |key|
                show(source, key)
            end
            self[:all_displays] = {
                source: source
            }
        else
            show(source, display)
            self[:all_displays] = {
                source: :none
            }
        end

        if !@lights_set && @light_present
            # Task 4: If lighting is available then we may want to update them
            lights_to_actual(@light_present)
        end
    end


    #
    # SOURCE MUTE AND AUDIO CONTROL
    #

    # Mutes both the display and audio
    # Unmute is performed by source switching
    def video_mute(display)
        display = display.to_sym
        disp_mod = system.get_implicit(display)

        disp_info = self[:outputs][display]
        unless disp_info[:output].nil?
            system[:Switcher].switch({0 => disp_info[:output]})
        end

        # Source switch will unmute some projectors
        if disp_mod.respond_to?(:mute)
            @would_mute = schedule.in(300) do
                @would_mute = nil
                disp_mod.mute
            end
        end

        # Remove the indicator icon
        self[display] = {
            source: :none
        }
    end


    # Helpers for all display audio
    def global_mute(val)
        mute = is_affirmative?(val)
        self[:master_mute] = mute
        self[:outputs].each do |key, value|
            if value[:no_audio].nil?
                mixer_id = value[:mixer_id]
                mixer_index = value[:mixer_mute_index] || value[:mixer_index] || 1

                system[:Mixer].mute(mixer_id, mute, mixer_index)
            end
        end
    end

    def global_vol(val)
        val = in_range(val, self[:vol_max], self[:vol_min])
        self[:master_volume] = val
        self[:outputs].each do |key, value|
            if value[:no_audio].nil?
                mixer_id = value[:mixer_id]
                mixer_index = value[:mixer_index] || 1

                system[:Mixer].fader(mixer_id, val, mixer_index)
            end
        end
    end


    def switch_mode(mode_name)
        logger.debug { "switch mode called for #{mode_name} -- #{!!@modes}" }

        return unless @modes

        mode = @modes[mode_name.to_s]
        if mode
            # Update the outputs
            self[:outputs] = ActiveSupport::HashWithIndifferentAccess.new.deep_merge((mode[:outputs] || {}).merge(setting(:outputs) || {}))
            @original_outputs = self[:outputs].deep_dup
            self[:current_mode] = mode_name

            # Update the inputs
            inps = (setting(:inputs) + (mode[:inputs] || [])) - (mode[:remove_inputs] || [])
            inps.each do |input|
                inp = setting(input) || mode[input]

                if inp
                    if mode[input]
                        self[input] = Set.new(inp + mode[input]).to_a
                        (self[input] || []).each do |source|
                            @input_tab_mapping[source.to_sym] = input
                        end
                    end
                end
            end
            self[:inputs] = inps

            # Power on the system and apply any custom presets
            begin
                powerup unless setting(:ignore_modes)
            ensure
                sys = system
                sys[:Mixer].trigger(mode[:audio_preset]) if mode[:audio_preset]
                sys[:Switcher].switch(mode[:routes]) if mode[:routes]
                sys[:Lighting].trigger(@light_group, mode[:light_preset]) if mode[:light_preset]
                sys[:VideoWall].preset(mode[:videowall_preset]) if mode[:videowall_preset]
            end
        else
            logger.warn "unabled to find mode #{mode_name} -- bad request?"
        end
    end



    #
    # SHUTDOWN AND POWERUP
    #

    def powerup
        switch_mode(@defaults[:default_mode]) if @defaults && @defaults[:default_mode]

        # Keep track of displays from neighboring rooms
        @setCamDefaults = true

        # cancel any delayed shutdown events

        # Turns on audio if off (audio driver)
        # Triggers PDU

        # Turns on lights
        if @light_default
            lights_to_actual(@light_default)
            @lights_set = false
        end


        self[:tab] = self[:inputs][0] if self[:inputs]
        self[:state] = :online
        wake_pcs


        # Is there a single display in that rooms?
        disp = system.get(:Display, 2)
        default_source = setting(:default_source)
        if disp.nil? && default_source
            present(default_source, self[:outputs].keys[0])
        end


        # defaults = {
            # routes: {input: [outputs]}
            # levels: {fader_id: [level, index]}
        #}
        sys = system
        sys[:Switcher].switch(@defaults[:routes]) if @defaults[:routes]

        mixer = sys[:Mixer]
        if @defaults[:levels]
            @defaults[:levels].each do |key, args|
                mixer.fader(key, *args)
            end
        end

        if @defaults[:on_preset]
            mixer.preset(@defaults[:on_preset])

        else
            # Output levels and mutes
            level = @defaults[:output_level]
            self[:outputs].each do |key, value|
                if value[:no_audio].nil? && value[:mixer_id]
                    args = {}
                    args[:ids] = value[:mute_id] || value[:mixer_id]
                    args[:muted] = false
                    args[:index] = value[:mixer_mute_index] || value[:mixer_index] if value[:mixer_mute_index] || value[:mixer_index]
                    args[:type] = value[:mixer_type] if value[:mixer_type]
                    mixer.mutes(args)

                    new_level = value[:default_level] || level
                    if new_level
                        args = {}
                        args[:ids] = value[:mixer_id]
                        args[:level] = new_level
                        args[:index] = value[:mixer_index] if value[:mixer_index]
                        args[:type] = value[:mixer_type] if value[:mixer_type]
                        mixer.faders(args)
                    end
                end
            end

            # Mic levels and mutes
            if self[:mics]
                level = @defaults[:mic_level]
                self[:mics].each do |mic|
                    new_level = mic[:default_level] || level

                    args = {}
                    args[:ids] = mic[:mute_id] || mic[:id]
                    args[:muted] = false
                    args[:index] = mic[:index] if mic[:index]
                    args[:type] = mic[:type] if mic[:type]
                    mixer.mutes(args)

                    if new_level
                        args = {}
                        args[:ids] = mic[:id]
                        args[:level] = new_level
                        args[:index] = mic[:index] if mic[:index]
                        args[:type] = mic[:type] if mic[:type]
                        mixer.faders(args)
                    end
                end
            end
        end
        # Turn on VC cameras
        start_cameras unless @no_cam_on_boot

        preview(self[self[:tab]][0])
    end


    def shutdown(all = false)
        if all
            perform_action(mod: :System, func: :shutdown_actual).then do
                unjoin
            end
        else
            unjoin.then do
                thread.schedule do
                    shutdown_actual
                end
            end
        end
    end

    def shutdown_actual
        # Shudown action on Lights
        if @light_shutdown
            lights_to_actual(@light_shutdown)
            @lights_set = false
        end

        switch_mode(@defaults[:shutdown_mode]) if @defaults[:shutdown_mode]

        mixer = system[:Mixer]

        # Unroutes
        # Turns off audio if off (audio driver)
        # Triggers PDU
        # Turns off lights after a period of time
        # Turns off other display types
        self[:outputs].each do |key, value|
            begin
                # Next if joining room
                next if value[:remote] && (self[key].nil? || self[key][:source] == :none)

                # Blank the source
                self[key] = {
                    source: :none
                }

                # Turn off display if a physical device
                if value[:no_mod].nil?
                    disp = system.get_implicit(key)
                    if disp.respond_to?(:power)
                        logger.debug "Shutting down #{key}"
                        disp.power(Off)
                    end

                    # Retract screens if one exists
                    screen_info = value[:screen]
                    unless screen_info.nil?
                        screen = system.get_implicit(screen_info[:module])
                        screen.up(screen_info[:index])
                    end

                    # Raise the lifter if one exists
                    if value[:lifter]
                        lift = system.get_implicit(value[:lifter][:module])
                        lift_cool_down = (value[:lifter][:cool_down] || 10) * 1000

                        # ensure the display doesn't turn on (we might still be booting)
                        @waiting_for = {}

                        schedule.in(lift_cool_down) do
                            lift.up(value[:lifter][:index] || 1)
                        end
                    end
                end

                # Turn off output at switch
                outputs = value[:output]
                if outputs
                    system[:Switcher].switch({0 => outputs})
                    system[:Switcher].switch({0 => self[:has_preview]}) if self[:has_preview]
                end

                # Mute the output if mixer involved
                if @defaults[:off_preset].nil? && value[:no_audio].nil? && value[:mixer_id]
                    args = {}
                    args[:ids] = value[:mute_id] || value[:mixer_id]
                    args[:muted] = true
                    args[:index] = value[:mixer_mute_index] || value[:mixer_index] if value[:mixer_mute_index] || value[:mixer_index]
                    args[:type] = value[:mixer_type] if value[:mixer_type]
                    mixer.mutes(args)
                end

            rescue => e # Don't want to stop powering off devices on an error
                logger.print_error(e, 'Error powering off displays: ')
            end
        end

        # TODO:: PDU

        if @defaults[:off_preset]
            mixer.preset(@defaults[:off_preset])

        elsif self[:mics]
            # Mic mutes
            self[:mics].each do |mic|
                args = {}
                args[:ids] = mic[:mute_id] || mic[:id]
                args[:muted] = true
                args[:index] = mic[:index] if mic[:index]
                args[:type] = mic[:type] if mic[:type]
                mixer.mutes(args)
            end
        end

        # Mute source level audio
        self[:sources].each do |key, source|
            mute_source(mixer, source, true) if source[:mixer_id]
        end
        self[:outputs] = @original_outputs.dup # Shouldn't need to be deep

        system.all(:Computer).logoff
        system.all(:Camera).power(Off)
        system.all(:Visualiser).power(Off)

        # Turn off video wall slave displays
        @vidwalls.each do |key, details|
            system.all(details[:module]).power(Off)
        end

        self[:state] = :shutdown
        self[:selected_tab] = ''
    end


    #
    # MISC FUNCTIONS
    #
    def start_cameras
        cams = system.all(:Camera)
        cams.power(On)
        if @setCamDefaults
            cams.preset('default')
            @setCamDefaults = false
        end
    end

    def camera_preset(input, preset)
        source = self[:sources][input.to_sym]
        cam = system.get(source[:mod], source[:index])
        if preset[:number]
            cam.recall_position(preset[:number].to_i)
        elsif preset[:lookup]
            cam.preset(preset[:lookup])
        end
    end

    def select_camera(input, output = nil)
        if output
            system[:Switcher].switch({input => output})
        else
            system[:VidConf].select_camera(input)
        end
    end

    def vc_content(outp, inp)
        vc = self[:sources][outp.to_sym]
        return unless vc && vc[:content]
        source = self[:sources][inp.to_sym]
        return unless source

        # Perform any subsource selection
        if source[:usb_output]
            if system.exists? :USB_Switcher
                system[:USB_Switcher].switch_to(source[:usb_output])
            end
        end

        if source[:local_switch]
            details = source[:local_switch]
            switch = system.get_implicit(details[:switcher])
            switch.switch({ details[:input] => 1 })
        end

        # Perform the primary switch
        if vc[:video_content_only]
            system[:Switcher].switch_audio({0 => vc[:content]})
            system[:Switcher].switch_video({source[:input] => vc[:content]})
        else
            system[:Switcher].switch({source[:input] => vc[:content]})
        end

        # So we can keep the UI in sync
        self[:vc_content_source] = inp
    end

    def wake_pcs
        system.all(:Computer).wake(setting(:broadcast))
    end


    # ------------------------
    # Lights in Joining System
    # ------------------------
    def lights_to(level)
        perform_action(mod: :System, func: :lights_to_actual, args: [level])
    end

    def lights_to_actual(level)
        if level.is_a? String
            level_name = level
            level_num = @light_mapping[level]
        else
            level_num = level
            level_name = @light_mapping[level]
        end

        system[:Lighting].trigger(@light_group, level_num)
        self[:light_level] = level_name

        @lights_set = true
    end


    # ------------------------------
    # Master Audio in Joining System
    # ------------------------------
    def share_volume(display, level)
        perform_action(mod: :System, func: :volume_actual, args: [display, level.to_f.round])
    end

    def volume_actual(display, level)
        self[:"#{display}_volume"] = level
    end

    def share_mute(display, muted)
        perform_action(mod: :System, func: :mute_actual, args: [display, muted])
    end

    def mute_actual(display, muted)
        self[:"#{display}_amute"] = muted
    end


    # -----------
    # POD SHARING (assumes single output)
    # -----------
    def do_share(value, source = nil)
        return if setting(:ignore_joining)

        if self[:sources][:sharing_input].nil? && source && self[:sources][source]
            disp_source = self[:sources][source]
            self[:Presenter_hide] = false # Just in case
            tab :Presenter
            present_actual(source, @sharing_output)
        else
            current = self[@sharing_output]
            current_source = current ? self[@sharing_output][:source] : :none

            if value == true && current_source != :sharing_input
                self[:Presenter_hide] = false # Just in case
                logger.debug { "Pod changing source #{@sharing_output} - current source #{current_source}" }

                @sharing_old_source = current_source.to_sym

                present_actual(:sharing_input, @sharing_output)
                tab :Presenter
                system[:Display].mute_audio

            elsif value == false && current_source == :sharing_input
                changing_to = @sharing_old_source == :none ? self[:sources].keys.first : @sharing_old_source
                changing_to = changing_to.to_sym
                logger.debug { "Pod reverting source #{changing_to}" }

                tab @input_tab_mapping[changing_to]
                present_actual(changing_to, @sharing_output)

                system[:Display].unmute_audio
            end
        end
    end

    def enable_sharing(value)
        self[:Presenter_hide] = @always_share ? false : !value

        if value == false
            switch_mode(@defaults[:default_mode]) if @defaults[:default_mode]
            do_share(false)
        else
            switch_mode(@defaults[:on_sharing_mode]) if @defaults[:on_sharing_mode]
        end
    end


    protected


    def mute_source(mixer, details, mute_state)
        args = {}
        args[:ids] = details[:mute_id] || details[:mixer_id]
        index = details[:mixer_mute_index] || details[:mixer_index]
        args[:index] = index if index
        args[:muted] = mute_state

        mixer.mutes(args)
    end

    def update_audio(source, disp_id, no_audio)
        current = self[disp_id]
        mixer = system[:Mixer]

        if current && current[:source]
            curr_source = current[:source]
            found_count = 0

            # Loop through displays and ensure this source
            # is only on a single output
            self[:outputs].keys.each do |key|
                found_count += 1 if self[key.to_sym][:source] == curr_source
            end

            if found_count <= 1
                curr_info = self[:sources][curr_source]
                mute_source(mixer, curr_info, true) if curr_info && curr_info[:mixer_id]
            end
        end

        # Grab the audio info
        orig = @original_outputs[disp_id]
        output = source.merge(orig)
        output.delete(:hide_audio) unless no_audio

        # Update the front end
        outputs = self[:outputs].dup
        outputs[disp_id] = output
        self[:outputs] = outputs

        # Unmute this source
        mute_source(mixer, output, false)
    end

    def show(source, display)
        disp_source = self[:sources][source]

        # We might not actually want to switch anything (support tab)
        # Especially if the room only as a single display (switch on tab select)
        return if disp_source[:ignore] && !disp_source[:server_only_source]

        self[:vol_max] = disp_source[:vol_max] || @original_max
        self[:vol_min] = disp_source[:vol_min] || @original_min

        # Check if the input source defines the audio
        if disp_source[:mixer_id] || disp_source[:use_display_audio]
            update_audio(disp_source, display, disp_source[:no_audio])
        end

        disp_info = self[:outputs][display]

        # Task 1: switch the display on and to the correct source
        unless disp_info[:no_mod]
            disp_mod = system.get_implicit(display)

            if disp_mod[:power] == Off || disp_mod[:power_target] == Off
                arity = disp_mod.arity(:power)
                wall_details = @vidwalls[display]
                wall_display = system.all(wall_details[:module]) if wall_details

                turn_on_display = proc {
                    # Check if we need to broadcast to turn it on
                    if setting(:broadcast) && check_arity(arity)
                        disp_mod.power(On, setting(:broadcast))
                        if wall_details
                            wall_display.power(On, setting(:broadcast))
                            wall_display.switch_to wall_details[:input]
                        end
                    else
                        disp_mod.power(On)
                        if wall_details
                            wall_display.power(On)
                            wall_display.switch_to wall_details[:input]
                        end
                    end

                    # Set default levels if it was off
                    if disp_info[:mixer_id]
                        disp_mod.mute_audio if disp_mod.respond_to?(:mute_audio)
                        disp_mod.volume(disp_mod[:volume_min] || 0) if disp_mod.respond_to?(:volume)
                    else
                        level = disp_info[:default_level] || @defaults[:output_level]
                        disp_mod.volume level if level
                    end
                }

                # Check if this display has a lifter attached
                if disp_info[:lifter]
                    lift = system.get_implicit(disp_info[:lifter][:module])
                    lift_index = disp_info[:lifter][:index] || 1
                    status_var = :"#{disp_info[:lifter][:binding] || :lifter}#{lift_index}"

                    if lift[status_var] == :down
                        turn_on_display.call
                    else
                        if @waiting_for[display]
                            @waiting_for[display] = turn_on_display
                        else
                            @waiting_for[display] = turn_on_display
                            schedule.in(disp_info[:lifter][:time] || '7s') do
                                action = @waiting_for[display]
                                if action
                                    @waiting_for.delete(display)
                                    action.call
                                end
                            end
                        end
                    end

                    lift.down(lift_index)
                else
                    turn_on_display.call
                end

            elsif disp_mod.respond_to?(:mute)
                if @would_mute
                    @would_mute.cancel
                    @would_mute = nil
                end
                disp_mod.unmute if disp_mod[:mute]
            end

            # Change the display input
            inp_src = disp_source[:source] || disp_info[:default_source]
            inp_src = disp_info[:input_mapping][inp_src] || inp_src if disp_info[:input_mapping]
            if inp_src && disp_mod[:input] != inp_src
                disp_mod.switch_to(inp_src)
            end

            # Change the display audio input
            if disp_source[:source_audio]
                disp_mod.switch_audio(disp_source[:source_audio])
            end

            # mute the audio if there is dedicated audio
            if disp_source[:audio_out]
                if disp_mod.respond_to?(:mute_audio)
                    disp_mod.mute_audio
                elsif disp_mod.respond_to?(:volume)
                    disp_mod.volume(disp_mod[:volume_min] || 0)
                end
            else
                disp_mod.unmute if disp_mod[:mute] # if mute status is defined
            end

            # We are looking at a VC source so we need to
            # Switch to any selected content source
            if disp_source[:content] && self[:vc_content_source]
                vc_content(source, self[:vc_content_source])
            end
        end


        # Task 2: switch the switcher if it meets the criteria below
        # -> if a switcher is available (check for module)
        # -> if the source has an input
        # -> if the display has an output
        if disp_source[:input] && disp_info[:output]
            switcher = system[:Switcher]
            switcher.switch({disp_source[:input] => disp_info[:output]})
            if disp_source[:audio_deembed]
                switcher.switch({disp_source[:input] => disp_source[:audio_deembed]})
            end
        end

        # Perform any custom tasks
        if disp_source[:custom_tasks]
            disp_source[:custom_tasks].each do |task|
                args = task[:args] || []
                method = task[:method]
                system.get_implicit(task[:module]).method_missing(method, *args)
            end
        end

        # Task 3: lower the screen if this display has one
        unless disp_info[:screen].nil?
            screen = system.get_implicit(disp_info[:screen][:module])
            screen.down(disp_info[:screen][:index])
        end

        # Provide the UI with source information
        tmp = {
            source: source,
            title: disp_source[:title],
            type: disp_source[:type]
        }
        tmp[:record_as] = disp_source[:record_as] if disp_source[:record_as]
        self[display] = tmp
    end

    # ------------------------------------
    # Wake on LAN power display management
    # ------------------------------------
    def warm_up_displays
        if setting(:broadcast)
            system.all(:Display).each do |display|
                arity = display.arity(:power)
                if check_arity(arity)
                    display.power(On, setting(:broadcast))
                    display.power Off
                end
            end

            @vidwalls.each do |key, details|
                display = system.get_implicit(key)
                if display
                    arity = display.arity(:power)
                    if check_arity(arity)
                        walldisp = system.all(details[:module])
                        walldisp.power(On, setting(:broadcast))
                        walldisp.power Off
                    end
                else
                    logger.error "Invalid video wall configuration!"
                end
            end
        end
    end

    def hard_off_displays
        system.all(:Display).each do |disp|
            disp.hard_off if disp.respond_to? :hard_off
        end

        @vidwalls.each do |key, details|
            display = system.get_implicit(key)
            if display.respond_to? :hard_off
                walldisp = system.all(details[:module])
                walldisp.hard_off
            else
                logger.error "Invalid video wall configuration!"
            end
        end
    end


    # Checks if the display support broadcasting power on
    def check_arity(arity)
        arity >= 2 || arity < 0
    end
end
