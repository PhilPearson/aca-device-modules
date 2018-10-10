require 'net/http'
require 'json'

module Senzo; end

class Senzo::Sensor
    include ::Orchestrator::Constants

    descriptive_name 'Senzo Occupancy Sensor'
    generic_name :Sensor
    implements :logic

    default_settings({
        api_key: '363497c3-7089-433a-9b20-671f57088cb7',
        desk_ids: ['Will', 'Steve', 'Cam', 'Meeting']
    })

    def on_load
        on_update
    end

    def on_update
        schedule.clear

        add_desks

        level_occupancy('Sydney')
        # Schedule every 2 minutes as sensors only update every 2 minutes anyway
        schedule.every('1m') do
            level_occupancy('Sydney')
        end
    end

    def add_desks
        # get the root node id
        logger.debug(setting(:desk_ids))
        @desk_ids = setting(:desk_ids)

        url = "https://backend.senzodata.com/api/user/me?apikey=#{setting(:api_key)}"
        ret = Net::HTTP.get(URI.parse(url))
        parsed = JSON.parse(ret) # parse the JSON string into a usable hash table
        @rootnodeid = parsed['rootnodeid'] # get root node id

        url = "https://backend.senzodata.com/api/node/structure/#{@rootnodeid}?apikey=#{setting(:api_key)}"
        ret = Net::HTTP.get(URI.parse(url))
        parsed = JSON.parse(ret) # parse the JSON string into a usable hash table"
        levels = parsed['children'] # list of levels/zones/rooms

        @desks = []
        levels.each { |l|
            # each level has a list of desks as it's children
            if l['info']['name'] == 'Sydney'
                l['children'].each { |d|
                    @desks.push(d['id'])
                }
                break
            end
        }
    end

    def level_occupancy(level_id)
        @desks.each { |desk_id|
            occupancy?(level_id, desk_id)
        }
    end

    def occupancy?(level_id, desk_id)
        url = "https://backend.senzodata.com/api/sensor/live/#{desk_id}?apikey=#{setting(:api_key)}"
        ret = Net::HTTP.get(URI.parse(url))
        parsed = JSON.parse(ret) # parse the JSON string into a usable hash table"
        occupancy = parsed[0]['inuse']
        desk_id = parsed[0]['name']
        self[desk_id] = occupancy
    end
end
