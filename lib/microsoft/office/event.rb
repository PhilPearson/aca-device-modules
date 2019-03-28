class Microsoft::Officenew::Event < Microsoft::Officenew::Model

    # These are the fields which we just want to alias or pull out of the O365 model without any processing
    ALIAS_FIELDS = {
        'start' => 'start',
        'end' => 'end',
        'subject' => 'subject',
        'attendees' => 'old_attendees',
        'iCalUId' => 'icaluid',
        'showAs' => 'show_as',
        'createdDateTime' => 'created'
    }

    NEW_FIELDS = [
        { new_key: 'start_epoch', method: 'datestring_to_epoch', model_params:['start'] },
        { new_key: 'end_epoch', method: 'datestring_to_epoch', model_params:['end'] },
        { new_key: 'room_ids', method: 'set_room_id', model_params:['attendees'] },
        { new_key: 'attendees', method: 'format_attendees', model_params:['attendees', 'organizer'] },
        { new_key: 'is_free', method: 'check_availability', model_params:['start', 'end'], passed_params: ['available_to', 'available_from'] }
    ]

    (hash_to_reduced_array(ALIAS_FIELDS) + NEW_FIELDS.map{|v| v[:new_key]}).each do |field|
        define_method field do
            @event[field]
        end
    end

    def initialize(client:, event:, available_to:nil, available_from:nil)
        @client = client
        @available_to = available_to
        @available_from = available_from
        @event = create_aliases(event, ALIAS_FIELDS, NEW_FIELDS, self)
    end

    def get_contacts
        @client.get_contacts(mailbox: @event['mail'])
    end

    attr_accessor :event, :available_to, :available_from

    protected 

    def datestring_to_epoch(date_object)
        ActiveSupport::TimeZone.new(date_object['timeZone']).parse(date_object['dateTime']).to_i
    end

    def set_room_id(attendees)
        room_ids = []
        attendees.each do |attendee|
            attendee_email = attendee['emailAddress']['address']
            # If this attendee is a room resource
            if attendee['type'] == 'resource'
                room_ids.push(attendee_email)
            end
        end
        room_ids
    end

    def format_attendees(attendees, organizer)
        internal_domains = [::Mail::Address.new(organizer['emailAddress']['address']).domain]
        new_attendees = []
        attendees.each do |attendee|
            attendee_email = attendee['emailAddress']['address']

            # Compare the domain of this attendee's email against the internal domain
            mail_object = ::Mail::Address.new(attendee_email)
            mail_domain = mail_object.domain
            is_visitor = !(internal_domains.map{|d|
                d.downcase
            }.include?(mail_domain.downcase))

            # Alias the attendee fields, mark whether this is a visitor and pull organisation details from the email
            attendee_object = {
                email: attendee_email,
                name: attendee['emailAddress']['name'],
                visitor: is_visitor,
                organisation: attendee_email.split('@')[1..-1].join("").split('.')[0].capitalize
            }
            new_attendees.push(attendee_object)
        end
        new_attendees
    end

    def check_availability(start_param, end_param, available_from, available_to)
        booking_start = ActiveSupport::TimeZone.new(start_param['timeZone']).parse(start_param['dateTime']).to_i
        booking_end = ActiveSupport::TimeZone.new(end_param['timeZone']).parse(end_param['dateTime']).to_i
        
        # Check if this means the room is unavailable
        booking_overlaps_start = booking_start < available_from && booking_end > available_from
        booking_in_between = booking_start >= available_from && booking_end <= available_to
        booking_overlaps_end = booking_start < available_to && booking_end > available_to
        if booking_overlaps_start || booking_in_between || booking_overlaps_end
            return false
        else
            return true
        end
    end
end