#!/usr/bin/env ruby

# Control a camera through uvcdynctrl
# Only tested with an old Logitech QuickCam PTZ
# It reads the list of controls available, so in theory it should
# work with other cameras.
#
# Only tested with Ruby 1.9. I am having some issues installing the Tk gem
# on 2.3.1
#
# Author::  Bruno Melli 12/3/2016
# License:: Distributes under the same terms as Ruby

require 'tk'

# This class holds info about all the controls available for the camera.

class Control
  attr_accessor :name, :flags, :type, :choices, :min, :max, :step, :default

  def initialize(name)
    @name = name
  end

  # Controls have different values depending on the control type.
  # This class parses the Values string and save them according to the
  # type of the control

  def set_values(values)
    case @type
    when /Dword/  # n .. n, step size: n
      if values =~ /(\d+)\s*\.\.\s*(\d+)\s*,\s*step size:\s*(\d+)/
        @min = $1.to_f
        @max = $2.to_f
        @step = $3.to_f
      else
        puts "-E- Unrecognized value format: #{values}"
      end
    when /Choice/ # 'choice 1'[val1], ......, 'choice n'[valn]
      @choices = Hash.new
      values.scan(/\s*'([^']+)'\[([^\]]+)\]/) do |c, v|
        @choices[v] = c
      end
    when /Button/
      # do nothing
    when /Boolean/
      # do nothing
    else
      puts "-E- Unrecognized control type #{@type}"
    end
  end

end

# This class 
class CamCtrl

  def initialize(args = {}.freeze)
    @@uvctrl = '/usr/bin/uvcdynctrl'

    # Hold the graphics control variables
    # The key for all of these hashes are the control string

    $vars = Hash.new       # TkVariables. Need to be global
    @labels = Hash.new     # Tk labels. Probably don't need to be saved
    @entries = Hash.new    # Tk components (combo box, buttons, ...)

    unless File.executable?(@@uvctrl)
      puts "-E- #{@@uvctrl} not found or not executable. Aborting"
      exit 1
    end
    parse_controls()
    create_gui
  end

  # ---------- Camera controls -------------

  # Send a command to the external program tha actually talks to the camera
  def send_command(comd, value)
    cmd = "#{@@uvctrl} -s '#{comd}' -- #{value}"
    log_info(cmd)
    `#{cmd}`
  end

  # tilt_up callback
  def tilt_up
    send_command('Tilt (relative)', -500)
  end

  # tilt_down callback
  def tilt_down
    send_command('Tilt (relative)', 500)
  end

  # pan_left callback
  def pan_left
    send_command('Pan (relative)', -700)
  end

  # pan_right callback
  def pan_right
    send_command('Pan (relative)', 700)
  end

  # reset_to_origin callback
  def reset_to_origin
    send_command('Pan Reset', 0)
    send_command('Tilt Reset', 0)
  end

  # buttons callback
  def toggle_button(button)
    send_command(button, $vars[button].value)
  end

  # sliding bar callbacks
  def sliding_bar(bar)
    send_command(bar, $vars[bar].value.to_i)
  end

  # combo box callbacks
  def combo_box(box)
    send_command(box, @choice_controls[box].choices.key($vars[box].value))
  end

  # ---------- Find out what the camera supports

  # Save controls in the appropriate control Hash.
  # Different controls are handled differently so I group like controls
  # in their own separate Hash

  def save_control(control)
    return if control.nil?
    case control.name
    when /Pan/, /Tilt/
      @motor_controls[control.name] = control
    else
      case control.type
      when /Dword/
        @slider_controls[control.name] = control
      when /Button/
        # This should be taken care of by the Pan and Tilt rule
        puts "-E- Unhandled Button type for #{control.name}"
      when /Boolean/
        @toggle_controls[control.name] = control
      when /Choice/
        @choice_controls[control.name] = control
      else
        puts "-E- Unrecognized control #{control.name} type #{control.type}"
      end
    end
  end

  # Call the external program to find out all the controls supported by the camera
  # Parse the result, creating and saving new controls as needed

  def parse_controls()
    puts "-I- Querying the camera..."

    @motor_controls = Hash.new  # Pan, Tilt
    @slider_controls = Hash.new # Brightness, Contrast, ...
    @toggle_controls = Hash.new # Auto (WB, exposure...)
    @choice_controls = Hash.new # Freq, exposure
    
    @device = ''

    current_control = nil

    `#{@@uvctrl} -c -v`.each_line do |l|
      l.chomp!
      
      if l =~ /Listing available .* video([0-9]+)/
        @device = "video#{$1}"
        puts "device: #{@device}"
        next
      end

      case l
      when /^\s*([^:]+)$/
        save_control(current_control)
        current_control = Control.new($1)
      when /^\s*Type\s+:\s+(\w+)/
        current_control.type = $1
        next
      when /^\s*Flags\s+:/
        next
      when /^\s*Values\s*:\s*\[\s*([^\]]+)\s+\],/
        current_control.set_values($1)
      when /^\s*Values\s*:\s*\{\s*([^\{]+)\s+\},/
        current_control.set_values($1)
      when /^\s*Default\s*:\s*([^\s]+)/
        current_control.default = $1.to_f
      end
    end
    save_control(current_control)
  end

  # ---------- These assume the GUI has been created
  # hey should probably be merged into one function

  # Write out an Info message to the message area of the GUI
  def log_info(msg)
    # puts "-I- #{msg}"
    @msg_text.insert('end', "-I- #{msg}\n")
    @msg_text.see('end')
  end

  # Write out an Error message to the message area of the GUI
  def log_error(msg)
    # puts "-E- #{msg}"
    @msg_text.insert('end', "-E- #{msg}\n")
    @msg_text.see('end')
  end

  
  # ---------------- The GUI creation ---------------------

  # Huge function to create the GUI
  # Tk is pretty verbose so this function is quite large.
  # It probably needs to be split into separate functions

  def create_gui
    
    # The root
    
    root = TkRoot.new { title "Camera Control" }
    TkGrid.columnconfigure root, 0, :weight => 1
    TkGrid.rowconfigure root, 0, :weight => 1

    # Enclosing frame

    content = Tk::Tile::Frame.new(root) { padding "5 5 12 12" }
    content.grid :sticky => 'nsew'

    # -------------- Controller Details frame --------------

    details = Tk::Tile::Labelframe.new(content) { text 'Image Control' }
    details.grid :column => 0, :row => 0, :sticky => 'nsew', :columnspan => 4
    details['borderwidth'] = 2

    # Entries in the details frame

    row = 0

    @slider_controls.keys.sort.each do |key|
      control = @slider_controls[key]
      $vars[key] = TkVariable.new
      $vars[key].value = control.default
      @labels[key] =  Tk::Tile::Label.new(details) { text "#{key}:" }
      @labels[key].grid :column => 0, :row => row, :sticky => 'ew'
      @entries[key] = Tk::Tile::Scale.new(details, variable: $vars[key]) {
        orient 'horizontal';
        length 300;
        from control.min.to_f;
        to control.max.to_f;
        command { tk_callback('sliding_bar', key) }
      }
      @entries[key].grid :column => 1, :row => row, :sticky => 'ew'

      val = Tk::Tile::Entry.new(details, :width => 6, :textvariable => $vars[key] )
      val.grid :column => 3, :row => row, :sticky => 'ew'
      row += 1
    end # each controls
    TkWinfo.children(details).each {|w| TkGrid.configure w, :padx => 5, :pady => 3}
    TkGrid.columnconfigure(content, 0,	:weight => 1) 
 
    # -------------- Toggle frame ---------------

    tf =  Tk::Tile::Labelframe.new(content) { 
      text 'Options';
      padding "5 5 12 12"
    }
    tf.grid :column => 0, :row => 2, :sticky => 'nsew', :columnspan => 6
    tf['borderwidth'] = 2

    column = 1
    row = 1
    @toggle_controls.keys.sort.each do |key|
      control = @toggle_controls[key]
      $vars[key] = TkVariable.new
      $vars[key].value = control.default
      @entries[key] = Tk::Tile::CheckButton.new(tf) {
        text key;
        command { tk_callback('toggle_button', key) }
        onvalue 1;
        offvalue 0;
        variable $vars[key]
      }
      @entries[key].grid :column => column, :row => row, :sticky => 'ew'
      row += 1
    end # toggle controls

    @choice_controls.keys.sort.each do |key|
      control = @choice_controls[key]

      # the label

      l = Tk::Tile::Label.new(tf) { text key }

      # the combo box

      $vars[key] = TkVariable.new
      $vars[key].value = control.choices[control.default.to_i.to_s]
      @entries[key] = Tk::Tile::Combobox.new(tf) { 
        textvariable $vars[key];
        values control.choices.values 
      }
      @entries[key].bind("<ComboboxSelected>") { combo_box(key)  }
      l.grid  :column => 2, :row => row, :sticky => 'ew'
      @entries[key].grid :column => 1, :row => row, :sticky => 'ew'
      row += 1
    end # choice controls

    # -------------- Motor control frame --------------

    # Only show this part if the camera supports motor controls

    if @motor_controls.size > 0
      
      mcf = Tk::Tile::Labelframe.new(content) { text 'Motor Controls' }
      mcf.grid :column => 0, :row => 3, :sticky => 'nsew', :columnspan => 6
      mcf['borderwidth'] = 4

      image_path = File.dirname(__FILE__) + '/imgs/'

      au = TkPhotoImage.new(:file => image_path + 'Arrow-Up-icon.gif')
      ad = TkPhotoImage.new(:file => image_path + 'Arrow-Down-icon.gif')
      al = TkPhotoImage.new(:file => image_path + 'Arrow-Left-icon.gif')
      ar = TkPhotoImage.new(:file => image_path + 'Arrow-Right-icon.gif')
      ri = TkPhotoImage.new(:file => image_path + 'reset.gif')

      tu = Tk::Tile::Button.new(mcf) {
        image au;
        command { tk_callback('tilt_up') }
      }
      tu.grid :column => 2, :row => 1, :stick => 'ew'

      td = Tk::Tile::Button.new(mcf) {
        image ad;
        command { tk_callback('tilt_down') }
      }
      td.grid :column => 2, :row => 3, :stick => 'ew'

      pl = Tk::Tile::Button.new(mcf) {
        image al;
        command { tk_callback('pan_left') }
      }
      pl.grid :column => 1, :row => 2, :stick => 'ew'

      pr = Tk::Tile::Button.new(mcf) {
        image ar;
        command { tk_callback('pan_right') }
      }
      pr.grid :column => 3, :row => 2, :stick => 'ew'

      ro = Tk::Tile::Button.new(mcf) {
        image ri;
        command { tk_callback('reset_to_origin') }
      }
      ro.grid :column => 2, :row => 2, :stick => 'ew'
    end

    # -------------- Message frame --------------

    mf = Tk::Tile::Labelframe.new(content) { text 'Messages' }
    mf.grid :column => 0, :row => 4, :sticky => 'nsew', :columnspan => 6
    mf['borderwidth'] = 2

    
    TkGrid.columnconfigure(mf, 0, :weight => 1)
    TkGrid.rowconfigure(mf, 0, :weight => 1)

    @msg_text = TkText.new(mf) { height 10; background "white" }
    @msg_text.grid :column => 0, :row => 2
    @msg_text['state'] = :normal

    TkWinfo.children(content).each {|w| TkGrid.configure w, :padx => 5, :pady => 5}
#    TkWinfo.children(data).each {|w| TkGrid.configure w, :padx => 5, :pady => 3}

  end # create_gui

end # class CamCtrl

# -------------------------- GUI callbacks ------------------------
# Apparently, Tk doesn't have access to instance methods.
# So I can't use the class methods as callbacks.

# Motor control

def tk_callback(name, *args)
  $ctrl.public_send(name, *args)
end

# ----------------------- Entry point -----------------

$ctrl = CamCtrl.new
Tk.mainloop
