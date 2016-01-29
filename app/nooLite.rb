require 'libusb'


class NooLite
  DEV_VID = 0x16c0
  DEV_PID = 0x05df

  class << self
    def bind(channel)
      execute_command(15, channel.to_i)
    end

    def unbind(channel)
      execute_command(9, channel.to_i)
    end

    def switch_on(channel)
      execute_command(2, channel.to_i)
    end

    def switch_off(channel)
      execute_command(0, channel.to_i)
    end

    def toggle(channel)
      execute_command(4, channel.to_i)
    end

    def set_brightness(channel, brightness)
      level = (brightness * 1.23 + 34).to_i

      execute_command(6, channel.to_i, 1, [level])
    end

    def set_color(channel, color)
       colors = color.scan(/.{2}/)

       execute_command(6, channel.to_i, 3, colors.map{|c| c.to_i(16)}) if colors.length == 3
    end



    def execute_command(action, channel, format=0, data=[])
      command = [0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

      command[1] = action if (0..19).include?(action)
      command[2] = format unless format.nil?
      command[4] = channel

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
