require 'libusb'


class NooLite
  DEV_VID = 0x16c0
  DEV_PID = 0x05df

  # Commands
  OFF                  = 0
  SMOOTH_OFF           = 1     # smooth version of the OFF action
  ON                   = 2
  SMOOTH_ON            = 3     # smooth version of the ON action
  TOGGLE               = 4
  SMOOTH_TOGGLE        = 5     # smooth version of the TOGGLE action
  SET                  = 6
  RUN_SCENARIO         = 7
  SAVE_SCENARIO        = 8
  UNBIND               = 9
  STOP_COLOR_PLAY      = 10
  BIND                 = 15
  START_COLOR_PLAY     = 16
  SWITCH_TO_NEXT_COLOR = 17
  CHANGE_SWITCH_MODE   = 18
  CHANGE_SWITCH_SPEED  = 19

  # Formats
  BRIGHTNESS = 1
  RGB        = 3
  CONTROL    = 4

###############################################################################
###############################################################################
###############################################################################

  class << self
    def bind(channel)
      execute_command(BIND, channel)
    end

###############################################################################

    def unbind(channel)
      execute_command(UNBIND, channel)
    end

###############################################################################

    def switch_on(channel, smooth = false)
      execute_command(smooth ? SMOOTH_ON : ON, channel)
    end

###############################################################################

    def switch_off(channel, smooth = false)
      execute_command(smooth ? SMOOTH_OFF : OFF, channel)
    end

###############################################################################

    def toggle(channel, smooth = false)
      execute_command(smooth ? SMOOTH_TOGGLE : TOGGLE, channel)
    end

###############################################################################

    def set_brightness(channel, brightness)
      level = (brightness * 1.23 + 34).to_i

      execute_command(SET, channel, BRIGHTNESS, [level])
    end

###############################################################################

    def set_color(channel, color)
       colors = color.scan(/.{2}/)

       execute_command(SET, channel, RGB, colors.map{|c| c.to_i(16)}) if colors.length == 3
    end


###############################################################################

    def start_color_play(channel)
       execute_command(START_COLOR_PLAY, channel, CONTROL)
    end

###############################################################################

    def stop_color_play(channel)
       execute_command(STOP_COLOR_PLAY, channel)
    end

###############################################################################

    def switch_to_next_color(channel)
       execute_command(SWITCH_TO_NEXT_COLOR, channel, CONTROL)
    end

###############################################################################

    def change_switch_mode(channel)
       execute_command(CHANGE_SWITCH_MODE, channel, CONTROL)
    end

###############################################################################

    def change_switch_speed(channel)
       execute_command(CHANGE_SWITCH_SPEED, channel, CONTROL)
    end

###############################################################################
###############################################################################
###############################################################################

    def execute_command(action, channel, format=0, data=[])
      command = [0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

      command[1] = action if (0..19).include?(action)
      command[2] = format unless format.nil?
      command[4] = channel.to_i

      if action == 6
        case format
        when 1 then
          command[5] = data[0]
        when 3 then
          # command[5] = data[0]
          # command[6] = data[2]
          # command[7] = data[1]
  
          # command[5] = data[2]
          # command[6] = data[0]
          # command[7] = data[1]

          command[5] = data[0]
          command[6] = data[1]
          command[7] = data[2]
        end
      end

      usb = LIBUSB::Context.new
      device = usb.devices(:idVendor => DEV_VID, :idProduct => DEV_PID).first

      raise "No device found" if device.nil?

      puts "\nExecuting command: #{command.inspect}\n"

      device.open_interface(0) do |handle|
        handle.control_transfer(
          :bmRequestType => 0x21,	# LIBUSB_REQUEST_TYPE_CLASS|LIBUSB_RECIPIENT_INTERFACE|LIBUSB_ENDPOINT_OUT
          :bRequest      => 0x09,
          :wValue        => 0x300,
          :wIndex        => 0x00,
          :dataOut       => command.pack('c*')
        )
      end
    end
  end
end
