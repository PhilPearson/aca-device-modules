require 'uv-rays'

# Documentation:
# https://www.cisco.com/c/en/us/td/docs/wireless/mse/10-2/api/b_cmx_102_api_reference/b-cmx-102-api-reference-guide_chapter_011.html

module Cisco; end
class Cisco::Cmx
    def initialize(host, user, pass, use_ou = nil, floor_mappings: nil, ssid: nil, api_version: 2)
        @host = UV::HttpEndpoint.new(host)
        @ldap = Array(use_ou)
        @floor_mappings = floor_mappings
        @ssid = Array(ssid) if ssid
        @path = "/api/location/v#{api_version}/clients"
        @headers = {
            authorization: [user, pass]
        }
    end

    def locate(user: nil, ip: nil, mac: nil, sort: 'lastLocatedTime:DESC')
        query = {}
        query[:sortBy] = sort if sort
        query[:ipAddress] = ip if ip
        query[:macAddress] = mac if mac

        if user && !@ldap.empty?
            resp = nil
            @ldap.each do |ou|
                query[:username] = "CN=#{user}#{ou}"
                resp = perform(query)
                break if resp
            end
            resp
        else
            query[:username] = user if user
            perform(query)
        end
    end

    protected

    def perform(query)
        resp = @host.get(path: @path, headers: @headers, query: query).value

        return nil if resp.status == 204
        raise "request failed #{resp.status}\n#{resp.body}" unless (200...300).include?(resp.status)

        locations = JSON.parse(resp.body, symbolize_names: true)
        locations.select! { |loc| @ssid.include?(loc[:ssId]) } if @ssid
        return nil if locations.length == 0

        map = locations[0][:mapInfo][:mapHierarchyString].split('>')
        campus = @floor_mappings[map[0]]
        building = @floor_mappings[map[1]]

        if building.is_a?(Hash)
            level = building[map[2]]
            zone = building[map[3]]
            building = building[:id]
        else
            level = @floor_mappings[map[2]]
            zone = @floor_mappings[map[3]]
        end

        {
            x: locations[0][:mapCoordinate][:x],
            y: locations[0][:mapCoordinate][:y],
            x_max: locations[0][:mapInfo][:floorDimension][:width],
            y_max: locations[0][:mapInfo][:floorDimension][:length],
            confidence: (locations[0][:confidenceFactor] / 2),
            last_seen: locations[0][:changedOn] / 1000,
            user_active: locations[0][:currentlyTracked],
            campus: campus || map[0],
            building: building || map[1],
            level: level || map[2],
            zone: zone || map[3],
            map_id: locations[0][:mapInfo][:floorRefId]
        }
    end
end
