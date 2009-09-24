require 'tty'

class Array
    def reverse_each_index
        len = self.length - 1
        while len >= 0
            yield len
            len -= 1
        end
    end
end

class String
    def String.char(c)
        s = String.new(' ')
        s[0] = c
        s
    end

    def replace_each_regexp(regexp)
        while x = self.match(regexp)
            self[regexp] = yield x
        end
    end
end


class SequenceHash < Hash
    class SequencePart
    end
    @@part = SequencePart.new

    def initialize
    end
    def part
        @@part
    end

    def insert(seq, value)
        #    puts "insert " + seq
        params_array = Array.new
        seq.replace_each_regexp(/%/) { |match|
            params_array << match.begin(0)
            ""
        }
        self.store(seq, { :proc => value, :params => params_array } )
        return if seq.length < 2

        (1...seq.length).each { |i|
            self.store(seq[0...i], @@part)
        }
    end

    def []=(seq, value)
        if seq.kind_of?(Array)
            seq.each { |i|
                insert(i, value)
            }
            return
        end
        insert(seq, value)
    end

end


#TerminalChar = Struct.new(:char, :attrs)
class TerminalChar
    attr_accessor :char
    attr_accessor :bold, :underlined, :blink, :inverse, :invisible
    attr_accessor :foreground_color, :background_color

    def initialize
        clear
    end

    def clear
        @char = 0
        @bold = false
        @underlined = false
        @blink = false
        @inverse = false
        @invisible = false
        @foreground_color = 0
        @background_color = 7
    end

end

class Point
    attr_accessor :x, :y
    def initialize(ix, iy)
        @x = ix
        @y = iy
    end
end

class TerminalBuffer
    attr_reader :last_output_raw

    def reset
        @origin_mode = false
        @scroll_region_top = 0
        @scroll_region_bottom = @size.y - 1
        @smooth_scroll = false
        @insert_mode = false
        @cursor_key_mode = :numeric
        @keypad_mode = :numeric
        @auto_wrap = false
        @cursor_visible = true
        @charset = :uk
        @tab_stops = Array.new

        @cursor = Point.new(0, 0)
        @buffer = Array.new(@size.y) { |i|
            Array.new(@size.x) { |j|
                TerminalChar.new
            }
        }

        @attributes = TerminalChar.new
        @cursor_stack = Array.new
    end

    def initialize(x, y)
        @size = Point.new(x, y)
        reset
        @cursor.y = y - 1
        @last_output_raw = ""

        @sequence_hash = SequenceHash.new

        # scroll mode - smooth/fast
        @sequence_hash["[?4h"] = Proc.new { @smooth_scroll = true }
        @sequence_hash["[?4l"] = Proc.new { @smooth_scroll = false }

        # auto wrap mode
        @sequence_hash["[?7h"] = Proc.new { @auto_wrap = true }
        @sequence_hash["[?7l"] = Proc.new { @auto_wrap = false }

        # cursor key mode
        @sequence_hash["[?1h"] = Proc.new { @cursor_key_mode = :application }
        @sequence_hash["[?1l"] = Proc.new { @cursor_key_mode = :numeric }

        # enter/exit application keypad mode
        @sequence_hash["="] = Proc.new { @keypad_mode = :application }
        @sequence_hash[">"] = Proc.new { @keypad_mode = :numeric }

        # cursor visibility
        @sequence_hash["[?25h"] = Proc.new { @cursor_visible = true }
        @sequence_hash["[?25l"] = Proc.new { @cursor_visible = false }

        # change charset
        @sequence_hash["(A"] = Proc.new { @charset = :uk }
        @sequence_hash["(B"] = Proc.new { @charset = :us }
        @sequence_hash["(0"] = Proc.new { @charset = :special }
        @sequence_hash["(1"] = Proc.new { @charset = :alternate }
        @sequence_hash["(2"] = Proc.new { @charset = :alternate_special }

        # mysterious mode
        @sequence_hash["[?1049h"] = Proc.new {}
        @sequence_hash["[?1049l"] = Proc.new {}
        @sequence_hash["[?12l"] = Proc.new {}
        @sequence_hash["[?12;25h"] = Proc.new {}

        # report cursor pos
        @sequence_hash["[r"] = Proc.new {}

        # erase in line - from cursor to end of line, including cursor position
        @sequence_hash[["K", "[K", "[0K"]] = Proc.new {
            @buffer[@cursor.y].each_index { |i|
                @buffer[@cursor.y][i].clear if i >= @cursor.x
            }
        }

        # erase in line - from beginning of line to cursor, including cursor pos
        @sequence_hash["[1K"] = Proc.new {
            @buffer[@cursor.y].each_index { |i|
                @buffer[@cursor.y][i].clear if i <= @cursor.x
            }
        }

        # erase in line - complete line
        @sequence_hash["[2K"] = Proc.new {
            @buffer[@cursor.y].each { |i|
                i.clear
            }
        }

        # erase in display - from cursor to end of screen, including cursor pos
        @sequence_hash[["J", "[J", "[0J"]] = Proc.new {
            @buffer.each_index { |j|
                if j == @cursor.y
                    @buffer[j].each_index { |i|
                        @buffer[j][i].clear if i >= @cursor.x
                    }
                elsif j > @cursor.y
                    @buffer[j].each { |i| i.clear }
                end
            }
        }

        # erase in display - from beginning of screen to cursor, incl cursor
        @sequence_hash["[1J"] = Proc.new {
            @buffer.each_index { |j|
                if j == @cursor.y
                    @buffer[j].each_index { |i|
                        @buffer[j][i].clear if i <= @cursor.x
                    }
                elsif j < @cursor.y
                    @buffer[j].each { |i| i.clear }
                end
            }
        }

        # erase in display - complete display
        @sequence_hash["[2J"] = Proc.new {
            @buffer.each_index { |j|
                @buffer[j].each { |i| i.clear }
            }
        }

        # insertion/replacement mode
        @sequence_hash["[4h"] = Proc.new { @insert_mode = true }
        @sequence_hash["[4l"] = Proc.new { @insert_mode = false }

        # reset
        @sequence_hash["c"] = Proc.new { reset }

        # save/restore cursor
        @sequence_hash["7"] = Proc.new {
            @cursor_stack.push( {
                                    :cursor => @cursor.dup,
                                    :attributes => @attributes.dup,
                                    :origin_mode => @origin_mode }
                                )
        }
        @sequence_hash["8"] = Proc.new {
            cs = @cursor_stack.pop
            if !cs
                if @origin_mode
                    @cursor.y = @scroll_region_top
                else
                    @cursor.y = 0
                end
                @cursor.x = 0
            else
                @cursor = cs[:cursor]
                @attributes = cs[:attributes]
                @origin_mode = cs[:origin_mode]
            end
        }


        def select_graphics_rendition(m)
            if m == 0
                @attributes.clear
#                @attributes.bold = false
#                @attributes.underlined = false
#                @attributes.blink = false
            elsif m == 1
                @attributes.bold = true
            elsif m == 4
                @attributes.underlined = true
            elsif m == 5
                @attributes.blink = true
            elsif m == 7
                @attributes.inverse = true
            elsif m == 8
                @attributes.invisible = true
            elsif m == 22
                @attributes.bold = false
            elsif m == 24
                @attributes.underlined = false
            elsif m == 25
                @attributes.blink = false
            elsif m == 27
                @attributes.inverse = false
            elsif m == 28
                @attributes.invisible = false
            elsif m >= 30 && m < 38
                @attributes.foreground_color = m - 30
            elsif m == 39
                @attributes.foreground_color = 0
            elsif m >= 40 && m < 48
                @attributes.background_color = m - 40
            elsif m == 49
                @attributes.background_color = 7                
            else
            end
        end

        # set top and bottom margins
        @sequence_hash["[%;%r"] = Proc.new { |top, bottom|
            top = 1 if !top
            bottom = size.y if !bottom
            top -= 1
            bottom -= 1
            next if top < bottom
            next if top < 0
            next if bottom >= size.y
            @scroll_region_top = top
            @scroll_region_bottom = bottom
        }

        # cursor positioning
        @sequence_hash["[%A"] = Proc.new { |by|
            by = 1 if !by
            @cursor.y -= by
            fix_cursor
        }
        @sequence_hash["[%B"] = Proc.new { |by|
            by = 1 if !by
            @cursor.y += by
            fix_cursor
        }
        @sequence_hash["[%C"] = Proc.new { |by|
            by = 1 if !by
            @cursor.x += by
            fix_cursor
        }
        @sequence_hash["[%D"] = Proc.new { |by|
            by = 1 if !by
            @cursor.x -= by
            fix_cursor
        }
        @sequence_hash["[%G"] = Proc.new { |by|
            by = 1 if !by
            by -= 1
            @cursor.x = by
            fix_cursor
        }
        @sequence_hash["[%d"] = Proc.new { |by|
            by = 1 if !by
            by -= 1
            @cursor.y = by
            fix_cursor
        }
        @sequence_hash[["[%;%H", "[%;%f"]] = Proc.new { |y, x|
            x = 1 if !x
            y = 1 if !y
            x -= 1
            y -= 1
            @cursor.x = x
            if @origin_mode
                @cursor.y = @scroll_region_top + y
            else
                @cursor.y = y
            end
            fix_cursor
        }
        # move cursor home
        @sequence_hash[["[H", "[f"]] = Proc.new {
            if @origin_mode
                @cursor.y = @scroll_region_top
            else
                @cursor.y = 0
            end
            @cursor.x = 0
        }

        # move up/down one line, scroll if at margin
        @sequence_hash["D"] = Proc.new {
            @cursor.y += 1
            bottom = @size.y - 1
            bottom = @scroll_region_bottom if @origin_mode
            if @cursor.y > bottom
                scroll_up
                @cursor.y = bottom
            end
        }
        @sequence_hash["M"] = Proc.new {
            @cursor.y -= 1
            top = 0
            top = @scroll_region_top if @origin_mode
            if @cursor.y < top
                scroll_down
                @cursor.y = top
            end
        }
        @sequence_hash["E"] = Proc.new {
            @cursor.y += 1
            bottom = @size.y - 1
            bottom = @scroll_region_bottom if @origin_mode
            if @cursor.y > bottom
                scroll_up
                @cursor.y = bottom
            end
            @cursor.x = 0
        }

        # insert or delete characters
        @sequence_hash["[%P"] = Proc.new { |by|
            by = 1 if !by
            @buffer[@cursor.y].each_index { |i|
                next if i < @cursor.x
                if i < @size.x - by
                    @buffer[@cursor.y][i] = @buffer[@cursor.y][i + by]
                else
                    @buffer[@cursor.y][i] = @buffer[@cursor.y][i].dup
                    @buffer[@cursor.y][i].char = 32
                end
            }
        }
        @sequence_hash["[%@"] = Proc.new { |by|
            by = 1 if !by
            @buffer[@cursor.y].reverse_each_index { |i|
                next if i < @cursor.x
                if i >= @size.x - by
                    @buffer[@cursor.y][i] = @buffer[@cursor.y][i - by]
                else
                    @buffer[@cursor.y][i] = @buffer[@cursor.y][i].dup
                    @buffer[@cursor.y][i].char = 32
                end
            }
        }

        @sequence_hash["[%;%m"] = Proc.new { |first, second|
            first = 0 if !first
            select_graphics_rendition(first)
            select_graphics_rendition(second) if second
        }
        @sequence_hash["[%m"] = Proc.new { |m|
            m = 0 if !m
            select_graphics_rendition(m)
        }

        # screen alignment display
        @sequence_hash["#8"] = Proc.new {
            @buffer.each_index { |j|
                @buffer[j].each { |i|
                    i.clear
                    i.char = 69
                }
            }
        }

        @sequence_hash[["Z", "[c", "[0c"]] = Proc.new {
            # TODO: identify
        }

        @sequence_hash["[%n"] = Proc.new { |n|
            n = 0 if !n
            if n == 5
                
            elsif n == 6
            end
        }

        # clear all tab stops
        @sequence_hash["[3g"] = Proc.new {
            @tab_stops.clear
        }

        # clear tab stop at cursor position
        @sequence_hash[["[g", "[0g"]] = Proc.new {
            @tab_stops.delete(@cursor.x)
        }

        # add tab stop at cursor position
        @sequence_hash["H"] = Proc.new {
            @tab_stops << @cursor.x
        }

#        @sequence_hash.each { |k, v|
#            puts k
#        }

    end

    def get
        @buffer
    end
    def get_cursor
        @cursor
    end
    def cursor_visible?
        @cursor_visible
    end

    def scroll_up
        @buffer.each_index { |i|
            next if i < @scroll_region_top
            next if i >= @scroll_region_bottom
            @buffer[i] = @buffer[i + 1]
        }
        @buffer[@scroll_region_bottom] = Array.new(@size.x) { ||
            TerminalChar.new
        }
    end

    def scroll_down
        @buffer.reverse_each_index { |i|
            next if i > @scroll_region_bottom
            next if i <= @scroll_region_top
            @buffer[i] = @buffer[i - 1]
        }
        @buffer[@scroll_region_top] = Array.new(@size.x) { ||
            TerminalChar.new
        }
    end

    def fix_cursor
        @cursor.x = 0 if @cursor.x < 0
        @cursor.x = @size.x - 1  if @cursor.x >= @size.x
        top = 0
        top = @scroll_region_top if @origin_mode
        bottom = @size.y - 1
        bottom = @scroll_region_bottom if @origin_mode
        @cursor.y = top if @cursor.y < top
        @cursor.y = bottom if @cursor.y > bottom
    end

    def advance_cursor
        @cursor.x += 1
        if @cursor.x == @size.x
            if @auto_wrap == false
                @cursor.x -= 1
                return
            end
            @cursor.x = 0
            @cursor.y += 1
        end
        if @cursor.y == @size.y
            scroll_up
            @cursor.y -= 1
        end
    end

    def print_char(char, pos)
        tc = @attributes.dup
        tc.char = char
        @buffer[pos.y][pos.x] = tc
    end

    def inc_vert
        @cursor.y += 1
        if @cursor.y == @size.y
            scroll_up
            @cursor.y -= 1
        end
    end

    def bell
        puts "ring"
    end

    def backspace
        @cursor.x -= 1 if @cursor.x > 0
    end

    def horizontal_tab
        @cursor.x = @cursor.x / 8 * 8 + 8
        if @cursor.x >= @size.x
            @cursor.x = 0
            inc_vert
        end
    end

    def linefeed
        @cursor.x = 0
        inc_vert
    end

    def carriage_return
        @cursor.x = 0
    end

    def cancel_sequence
        @sequence = nil
    end
    def start_sequence
        @sequence = String.new
    end

    def proc_sequence(c)
        @sequence += String.char(c)

        p = @sequence_hash[@sequence]
        if !p
        elsif p == @sequence_hash.part
            # part of valid sequence
            return
        elsif p[:params].size == 0
            # sequence found
#            puts "found " + @sequence
            @sequence = nil
            p[:proc].call
            return
        end

        sequence_dup = @sequence.dup

        params = Hash.new
        sequence_dup.replace_each_regexp(/[0-9]+/) { |match|
            params[match.begin(0)] = match.to_s.to_i
            ""
        }

        p = @sequence_hash[sequence_dup]
        if p == @sequence_hash.part
            # part of valid parameterized sequence
            return
        elsif p
            # found
#            puts "found param " + @sequence
            @sequence = nil
            args = Array.new
            p[:params].each { |offset|
#                puts "  args " + params[offset].to_s
                args << params[offset]
            }
            p[:proc].call(*args)
            return
        end
        # not part of any known valid sequence
        puts "drop " + @sequence
        cancel_sequence
    end

    def proc_char(c)
        if @sequence
            proc_sequence(c)
            return
        end

        if c < 32
            # got control character
            if c == 7
                bell
            elsif c == 8
                backspace
            elsif c == 9
                horizontal_tab
            elsif c == 10 || c == 11 || c == 12
                linefeed
            elsif c == 13
                carriage_return
            elsif c == 24
                cancel_sequence
            elsif c == 27
                start_sequence
            end
        else
            print_char(c, @cursor)
            advance_cursor
        end
    end

    def input(string)
        string.each_byte { |c|
            proc_char(c)
            #      puts "byte " + c.to_s
        }

        @last_output_raw += string
        if @last_output_raw.size > 1000
            @last_output_raw[0..(@last_output_raw.size - 1000)] = ""
        end
    end

    def get_bottom_line
        ret = ""
        @buffer[@size.y - 1].each { |c|
            x = c.char
            if x < 32 || x > 127
                x = 32
            end
            ret += String.char(x)
        }
        return ret
    end
end


def create_terminal
    x = TTY.forkpty
    if x == 0
        exec("/bin/bash")
        exit
    end

    return IO.new(x)
end

