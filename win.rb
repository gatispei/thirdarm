require 'rubygems'
require 'wx'
require 'term'




class TerminalFrame < Wx::Frame
    DEFAULT_SIZE = Wx::Size.new(80, 24)

    def init_font dc
        @font = Wx::Font.new(10, Wx::FONTFAMILY_MODERN, Wx::FONTSTYLE_NORMAL,
                             Wx::FONTWEIGHT_NORMAL)
        dc.set_font @font
        @font_size = Point.new(0, 0)
        @font_size.x, @font_size.y, descent, external_leading =
            dc.get_text_extent("W")

        printf("font size: %d*%d\n", @font_size.x, @font_size.y)
        @screen_size = DEFAULT_SIZE
        printf("screen size: %d*%d\n", @screen_size.x, @screen_size.y)
        set_background_colour(Wx::WHITE)
        set_client_size(Wx::Size.new(@screen_size.x * @font_size.x,
                                     @screen_size.y * @font_size.y))

        @buffer = TerminalBuffer.new(@screen_size.x, @screen_size.y)
    end

    def convert_color(col)
        case col
        when 0
            return Wx::BLACK
        when 1
            return Wx::RED
        when 2
            return Wx::GREEN
        when 3
            return Wx::YELLOW
        when 4
            return Wx::BLUE
        when 5
            return Wx::MAGENTA
        when 6
            return Wx::CYAN
        when 7
            return Wx::WHITE
        else
            return Wx::LIGHT_GREY
        end
    end
    def get_background(term_char)
        return convert_color(term_char.background_color) if !term_char.inverse
        return convert_color(term_char.foreground_color)
    end
    def get_foreground(term_char)
        return convert_color(term_char.foreground_color) if !term_char.inverse
        return convert_color(term_char.background_color)
    end
    def get_font(term_char)
        if term_char.bold || term_char.blink
            @font.set_weight(Wx::FONTWEIGHT_BOLD)
        else
            @font.set_weight(Wx::FONTWEIGHT_NORMAL)
        end
        @font.set_underlined(term_char.underlined)
        @font
    end

    def initialize(io)
        super(nil, -1, "Terminal")

        @io = io

        evt_size { |event| on_size(event) }
        evt_paint :on_paint

        @font = nil
        init_font(Wx::WindowDC.new(self))

        @iotimer = Wx::Timer.new(self, 123)
        @iotimer.start(100)
        evt_timer 123, :on_timer
        evt_char { |event| on_char(event) }
    end

    def on_size(event)
    end

    def on_paint
        paint { |dc|
            #      puts "paint"
            dc.set_font(@font)
            dc.set_background_mode(Wx::SOLID)
            b = @buffer.get
            b.each_index { |y|
                b[y].each_index { |x|
                    tc = b[y][x]
                    dc.set_font(get_font(tc))
                    dc.set_text_background(get_background(tc))
                    dc.set_text_foreground(get_foreground(tc))
                    s = String.char(tc.char)
                    dc.draw_text(s, @font_size.x * x, @font_size.y * y)
                }
            }
            if @buffer.cursor_visible?
                dc.draw_rectangle(@buffer.get_cursor.x * @font_size.x,
                                  @buffer.get_cursor.y * @font_size.y,
                                  @font_size.x, @font_size.y)
            end
        }
    end

    def on_timer
        begin
            input_string = @io.read_nonblock(1024)
        rescue EOFError
            close
        rescue SystemCallError
            #      puts "err: " + $!
        end
        if input_string && input_string.size
            #      puts "got input: " + input_string
            @buffer.input(input_string)
            refresh
        end
    end

    def on_special_key(code)
        #    puts "on special " + code.to_s
        if code == Wx::K_UP
            s = "[A"
        elsif code == Wx::K_DOWN
            s = "[B"
        elsif code == Wx::K_RIGHT
            s = "[C"
        elsif code == Wx::K_LEFT
            s = "[D"
        elsif code == Wx::K_END
            s = "[8~"
        elsif code == Wx::K_HOME
            s = "[7~"
        elsif code == Wx::K_INSERT
            s = "[2~"
        elsif code == Wx::K_DELETE
            s = "[3~"
        elsif code == Wx::K_NUMPAD0
            s = "Op"
        elsif code == Wx::K_NUMPAD1
            s = "Oq"
        elsif code == Wx::K_NUMPAD2
            s = "Or"
        elsif code == Wx::K_NUMPAD3
            s = "Os"
        elsif code == Wx::K_NUMPAD4
            s = "Ot"
        elsif code == Wx::K_NUMPAD5
            s = "Ou"
        elsif code == Wx::K_NUMPAD6
            s = "Ov"
        elsif code == Wx::K_NUMPAD7
            s = "Ow"
        elsif code == Wx::K_NUMPAD8
            s = "Ox"
        elsif code == Wx::K_NUMPAD9
            s = "Oy"
        elsif code == Wx::K_F1
            s = "OP"
        elsif code == Wx::K_F2
            s = "OQ"
        elsif code == Wx::K_F3
            s = "OR"
        elsif code == Wx::K_F4
            s = "OS"
        elsif code == Wx::K_F5
            s = "15~"
        elsif code == Wx::K_F6
            s = "17~"
        elsif code == Wx::K_F7
            s = "18~"
        elsif code == Wx::K_F8
            s = "19~"
        elsif code == Wx::K_F9
            s = "20~"
        elsif code == Wx::K_F10
            s = "21~"
        elsif code == Wx::K_F11
            s = "23~"
        elsif code == Wx::K_F12
            s = "24~"
        else
            return
        end
        s = String.char(27) + s
        @io.write(s)
    end

    def on_char(event)
        key = event.get_key_code()

        # handle cmd-W
        if event.meta_down && key == 119
            close
            return
        end

        if key < 128
            begin
                @io.write(String.char(key))
            rescue Errno::EPIPE
                close
            end
        else
            on_special_key(key)
        end

        #    puts "got output: " + key.to_s
    end
end


class TerminalApp < Wx::App

    def on_init
        frame = TerminalFrame.new(create_terminal)
        #    Wx::StaticText.new(frame, -1, "Static hello")
        frame.show()
    end

    def on_exit
    end
end


orig_cols, orig_rows = TTY.get_winsize(0)
TTY.set_winsize(0, 80, 24)

TerminalApp.new.main_loop

TTY.set_winsize(0, orig_cols, orig_rows)



