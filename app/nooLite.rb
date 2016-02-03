require 'libusb'


class NooLite
  DEV_VID = 0x16c0
  DEV_PID = 0x05df

  # Commands
  OFF                   = 0
  START_SMOOTH_DECREASE = 1
  ON                    = 2
  START_SMOOTH_INCREASE = 3
  TOGGLE                = 4
  REVERSE_SMOOTH        = 5
  SET                   = 6
  RUN_SCENARIO          = 7
  SAVE_SCENARIO         = 8
  UNBIND                = 9
  STOP_SMOOTH           = 10
  BIND                  = 15
  START_SMOOTH          = 16
  SWITCH_COLOR          = 17
  SWITCH_MODE           = 18
  SWITCH_SPEED          = 19

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

    def switch_on(channel)
      execute_command(ON, channel)
    end

###############################################################################

    def switch_off(channel)
      execute_command(OFF, channel)
    end

###############################################################################

    def toggle(channel)
      execute_command(TOGGLE, channel)
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

    def start_smooth_color_roll(channel)
       execute_command(START_SMOOTH, channel, CONTROL)
    end

###############################################################################

    def stop_smooth_roll(channel)
       execute_command(STOP_SMOOTH, channel)
    end

###############################################################################

    def switch_color(channel)
       execute_command(SWITCH_COLOR, channel, CONTROL)
    end

###############################################################################

    def switch_mode(channel)
       execute_command(SWITCH_MODE, channel, CONTROL)
    end

###############################################################################

    def switch_speed(channel)
       execute_command(SWITCH_SPEED, channel, CONTROL)
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
          command[5] = data[0]
          command[6] = data[1]
          command[7] = data[2]
        end
      end

      usb = LIBUSB::Context.new
      device = usb.devices(:idVendor => DEV_VID, :idProduct => DEV_PID).first

      raise "No device found" if device.nil?

      logger.info "\nExecuting command: #{command.inspect}\n"

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
