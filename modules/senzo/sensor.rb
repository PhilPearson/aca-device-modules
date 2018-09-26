# frozen_string_literal: true

require 'net/http'
require 'json'

# Manual desk tracking will use this DB structure for persistance
require 'aca/tracking/switch_port'
require 'set'

module Senzo; end

class Senzo::Sensor
    include ::Orchestrator::Constants

    descriptive_name 'Senzo Occupancy Sensor'
    generic_name :Sensor
    implements :logic

    default_settings({
        api_key: '363497c3-7089-433a-9b20-671f57088cb7',
        checkin: {
            Sydney: ['Will', 'Steve', 'Cam', 'Meeting room']
        },
        desk_hold_time: 5.minutes.to_i,
        desk_reserve_time: 2.hours.to_i,
        manual_reserve_time: 2.hours.to_i,
    })

    def on_load
        on_update
    end

    def on_update
        schedule.clear

        url = "https://backend.senzodata.com/api/user/me?apikey=#{setting(:api_key)}"
        ret = Net::HTTP.get(URI.parse(url))
        parsed = JSON.parse(ret) # parse the JSON string into a usable hash table
        @rootnodeid = parsed['rootnodeid'] # get root node id

        self[:hold_time] = setting(:desk_hold_time) || 5.minutes.to_i
        self[:reserve_time] = @desk_reserve_time = setting(:desk_reserve_time) || 2.hours.to_i
        self[:manual_reserve_time] = @manual_reserve_time = setting(:manual_reserve_time) || 2.hours.to_i

        # { level_id: ["desk_id1", "desk_id2", ...] }
        @manual_checkin = setting(:checkin) || {}
        @manual_usage = {} # desk_id => username
        @manual_users = Set.new

        level_occupancy('Sydney', @rootnodeid)
        schedule.every('2m') do
            level_occupancy('Sydney', @rootnodeid)
        end
    end

    def level_occupancy(level_id, rootnodeid)
        url = "https://backend.senzodata.com/api/node/structure/#{rootnodeid}?apikey=#{setting(:api_key)}"
        ret = Net::HTTP.get(URI.parse(url))
        parsed = JSON.parse(ret) # parse the JSON string into a usable hash table"
        levels = parsed['children']

        levels.each { |l|
            if l['info']['name'] == level_id
                @desks = l['children']
                break;
            end
        }

        @desks.each { |d|
            desk_id = d['id']
            occupancy?(desk_id)
        }

    end

    def occupancy?(desk_id)
        url = "https://backend.senzodata.com/api/sensor/live/#{desk_id}?apikey=#{setting(:api_key)}"
        ret = Net::HTTP.get(URI.parse(url))
        parsed = JSON.parse(ret) # parse the JSON string into a usable hash table"
        occupancy = parsed[0]['inuse']
        desk_id = parsed[0]['name']

        logger.debug "#{desk_id}\'s occupancy is #{occupancy}"
        if occupancy && @manual_usage[desk_id].nil?
            manual_checkin(desk_id)
        else
            force_checkout(desk_id)
        end
    end

    # For desks that use sensors
    #
    # @param desk_id [String] the unique id that represents a desk
    # @param level_id [String] the level id of the floor - saves processing if you have it handy
    def manual_checkin(desk_id, level_id = nil)
        raise "desk #{desk_id} already in use" unless @manual_usage[desk_id].nil?

        # Find the level if this was unknown
        if level_id.nil?
            @manual_checkin.each do |level, desks|
                if desks.include? desk_id
                    level_id = level
                    break
                end
            end
        end

        # Update the details to indicate that this is a manual desk
        details = {}
        details [:desk_id] = desk_id
        details[:level] = level_id
        details[:connected] = true
        details[:manual_desk] = true
        details[:clash] = false

        # Configure the desk to look occupied on the map
        @manual_usage[desk_id] = desk_id
        self[desk_id] = details
    end

    # For use with sensor systems
    #
    # @param desk_id [String] the unique id that represents a desk
    def force_checkout(desk_id)
        username = @manual_usage[desk_id]
        return unless username
        manual_checkout(self[username])
    end

    def manual_checkout(details, user_initiated = true)
        desk_id = details[:desk_id]
        username = details[:username] || desk_id

        @manual_usage.delete(desk_id)
        @manual_users.delete(username)
        details = details.dup
        details[:connected] = false
        details[:reserve_time] = 0 if user_initiated
        details[:released_at] = Time.now.to_i
        self[username] = details
    end
end
