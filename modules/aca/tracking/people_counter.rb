module Enumerable
  def each_with_previous
    self.inject(nil){|prev, curr| yield prev, curr; curr}
    self
  end
end

module Aca; end
module Aca::Tracking; end

class Aca::Tracking::PeopleCounter
    include ::Orchestrator::Constants
    include Orchestrator::StateBinder
    descriptive_name 'ACA People Count'
    generic_name :Count
    implements :logic

    bind :VidConf, :people_count, to: :count_changed

    bind :Bookings, :today, to: :booking_changed

    durations = []
    total_duration = 0
    @todays_bookings = nil
    events = []

    def booking_changed(details)
        return if details.nil?
        @todays_bookings = details
        details.each do |meeting|
            schedule.at(meeting[:End]) {
                calculate_average(meeting)
            }
        end
        
    end

    def get_current_booking(details)
        start_time = Time.now.to_i
        # For every meeting
        details.each do |meeting|
            # Grab the start and end
            meeting_start = Time.at(meeting[:start_epoch]).to_i
            meeting_end = Time.at(meeting[:start_epoch]).to_i

            # If it's past the start time and before the end time
            if start_time >= meeting_start && start_time < meeting_end 
               return meeting
            end
        end
    end

    def count_changed(new_count)
        logger.info "Count changed: #{new_count}"

        # Check the current meeting
        current = get_current_booking(@todays_bookings)

        # Add the change to the dataset for that meeting
        current_dataset = Aca::Tracking::PeopleCount.find_by_id("count-#{current[:id]}") || create_dataset(new_count, current)

        # Check if the new count is max
        dataset.maximum = new_count if new_count > dataset.maximum

        # Update the dataset with the new count
        current_dataset.counts.push(Time.now.to_i, new_count)

        # Save it back
        current_dataset.save!
    end

    def create_dataset(count, booking)
        logger.info "Creating a dataset"
        dataset = Aca::Tracking::PeopleCount.new

        # # Dataset attrs
        # attribute :room_email,   type: String  
        # attribute :booking_id,   type: String  
        # attribute :system_id,    type: String  
        # attribute :capacity,     type: Integer 
        # attribute :maximum,      type: Integer 
        # attribute :average,      type: Integer 
        # attribute :median,       type: Integer
        # attribute :organiser,    type: String
        
        dataset.room_email = system.email
        dataset.system_id = system.id
        dataset.capacity = system.capacity
        dataset.maximum = count
        dataset.average = count
        dataset.median = count
        dataset.booking_id = booking[:id]
        dataset.organiser = booking[:owner]
        dataset.id = "count-#{booking[:id]}"
        logger.info "Created dataset with ID: #{dataset.id}"
        return dataset if dataset.save!
    end

    def calculate_average(meeting) 
        logger.info "Calculating average for: #{meeting[:id]}"
        
        # Set up our holding vars
        durations = []
        total_duration = 0

        # Get the dataset
        dataset = ::Aca::Tracking::PeopleCount.find_by_id("count-#{meeting[:id]}") 

        events = dataset.counts

        # Calculate array of weighted durations
        events.each_with_previous do |prev, curr|
            if prev
                time = curr[0]
                count = curr[1]
                prev_time = prev[0]
                prev_count = prev[1]
                durations[prev_count] ||= 0
                durations[prev_count] += (time - prev_time)
                total_duration += (time - prev_time)
            end
        end

        # Remove nils
        durations = durations.each_with_index.map {|x,y| [x,y] }.delete_if { |x| x[0].nil? }

        # Generate weighted average
        running_total = 0
        average = nil
        durations.each {|reading|
            duration = reading[0]
            count = reading[1]
            running_total += duration
            if running_total / total_duration > 0.5
                average = reading[1]
                break
            end
        }

        dataset.average = average
        dataset.save!

        return average
    end


    def on_load
        on_update
    end

    def on_update
        self[:name] = system.name
        self[:views] = 0
        self[:state] = 'Idle'
        self[:todays_bookings] = []
        schedule.clear
        logger.info "Starting booking update in 30s"
        schedule.in('10s') { 
            logger.info "Grabbing bookings to update"
            self[:todays_bookings] = system[:Bookings][:today]
            booking_changed(self[:todays_bookings])
        }
    end

    def update_state
        if self[:state] == 'Stopped'
            state('Idle')
        end
        self[:views] += rand(7)
    end

    def state(status)
        self[:state] = status
    end
end