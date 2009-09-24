
TerminalEvent = Struct.new(:regexp, :status, :at, :callback)


class TerminalEventHandler

    def initialize(buffer)
        @buffer = buffer
        @listeners = {}

    end


    def prompt_on(regexp, callback)
        @listeners[regexp] = TerminalEvent.new(regexp, false, :on, callback)
    end
    def prompt_off(regexp, callback)
        @listeners[regexp] = TerminalEvent.new(regexp, false, :off, callback)
    end

    def delete(regexp)
        @listeners.delete(regexp)
    end


    def buffer_changed
        prompt = @buffer.get_bottom_line
        @listeners.each { |regexp, event|
#            puts "iii #{prompt.size}"
            new_status = false
            if prompt[regexp]
                new_status = true
            end

            if new_status != event.status
                if new_status && event.at == :on
                    event.callback.call
                end
                if !new_status && event.at == :off
                    event.callback.call
                end
                event.status = new_status
            end

        }
    end

end

