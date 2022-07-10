 ###############################################################################
 #  Copyright 2011 Ian McIntosh <ian@openanswers.org>
 #
 #  This program is free software; you can redistribute it and/or modify
 #  it under the terms of the GNU General Public License as published by
 #  the Free Software Foundation; either version 2 of the License, or
 #  (at your option) any later version.
 #
 #  This program is distributed in the hope that it will be useful,
 #  but WITHOUT ANY WARRANTY; without even the implied warranty of
 #  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 #  GNU Library General Public License for more details.
 #
 #  You should have received a copy of the GNU General Public License
 #  along with this program; if not, write to the Free Software
 #  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 ###############################################################################

require 'unique_timeout'
require_relative 'ruler_popup_menu'

Unit = Struct.new('Unit', :name, :tick_pattern, :units_per_pattern_repetition, :per_inch)

class RulerWindow < GladeWindow
	DEFAULT_RULER_LENGTH = 600

	MOVE_SMALL, MOVE_LARGE = 1, 15
	GROW_SMALL, GROW_LARGE = 1, 15

	ORIENTATION_LEFT, ORIENTATION_UP = 'left', 'up'		# where the value '0 pixels' is

	MENU_BOX_WIDTH, MENU_BOX_HEIGHT = 10, 10
	MENU_BOX_RELIEF = 10															# distance from edge

	OVERDRAW = 200		# ensures that final tick labels get drawn, even when the tick itself is past the window

	MEASUREMENT_TOOLTIP_UPDATE_FREQUENCY = 80					# in milliseconds

	@@unit_settings = {
		UNIT_INCHES				=> Unit.new('in', 'MMMLMMML',			1,	1),
		UNIT_CENTIMETERS	=> Unit.new('cm', 'MMMMLMMMML', 	1,	0.3937),
		UNIT_PICAS				=> Unit.new('pc', 'MMLMML', 			6,	0.1667),
		UNIT_POINTS				=> Unit.new('pt', 'MMMMMLMMMMML',	72,	0.0139),
		UNIT_PIXELS				=> Unit.new('px', 'SSSSMSSSSMSSSSMSSSSMSSSSL' * 2, 100, -1),	# :per_inch not used...
		UNIT_PERCENTAGE		=> Unit.new('%',  'ML',						10,	-1)											# ...ditto
	}.freeze

	@@tick_sizes = {'S' => 4, 'M' => 7, 'L' => 10}.freeze		# length of tick marks (in pixels) in above patterns

	def initialize
		super('ruler_window')

		self.icon_list = APP_ICON_LIST

		# Fill our window with a Drawing Area to render the ruler
		@drawing_area = Gtk::DrawingArea.new
		add(@drawing_area)
		@drawing_area.signal_connect('draw') do
			draw
		end

		@mouse_is_in_window = false	# we'll get a notify right away if mouse begins in the window
		@orientation = ORIENTATION_LEFT
		configure_ppi
		configure_orientation

		# GTK signal handlers are hooked up by Glade, let them be unmasked
		self.add_events(
			Gdk::EventMask::POINTER_MOTION_MASK |
			Gdk::EventMask::ENTER_NOTIFY_MASK |
			Gdk::EventMask::LEAVE_NOTIFY_MASK
		)

		@measurement_tooltip_timeout = UniqueTimeout.new(MEASUREMENT_TOOLTIP_UPDATE_FREQUENCY) { update_measurement_tooltip }
	end

	def present
		super
		self.opacity = $preferences_window.opacity if self.respond_to? :opacity=
	end

	def show_measurement_tooltip=(val)
		if val
			@measurement_tooltip_timeout.start
		else
			@measurement_tooltip_timeout.stop
		end
		@enable_mouse_tracking = val
		@drawing_area.queue_draw
	end

	def update_measurement_tooltip
		# Force a redraw if mouse has moved
		_window, mouse_x, mouse_y, key_mask = self.root_window.pointer
		if mouse_x != @previous_mouse_x || mouse_y != @previous_mouse_y || key_mask != @previous_key_mask
			# save for later comparison
			@previous_mouse_x, @previous_mouse_y, @previous_key_mask = mouse_x, mouse_y, key_mask
			@drawing_area.queue_draw
		end
	end

	def progress_pixels_to_unit_string(progress_pixels)
		unit = @@unit_settings[$ruler_popup_menu.unit]

		case $ruler_popup_menu.unit
		when UNIT_PIXELS
			sprintf("%d %s", progress_pixels, unit.name)
		when UNIT_PERCENTAGE
			sprintf("%3.1f %%", 100.0 * progress_pixels.to_f / length.to_f)
		else
			sprintf("%3.2f %s", (progress_pixels.to_f / pixels_per_inch) / unit.per_inch, unit.name)
		end
	end

	def on_delete_event
		Gtk.main_quit
		true	# handled
	end

	def length
		w, h = self.size
		case @orientation
			when ORIENTATION_LEFT	then w
			when ORIENTATION_UP		then h
		end
	end

	def length=(value)
		grow(value - length)
	end

	def pixels_per_inch
		case @orientation
			when ORIENTATION_LEFT	then $preferences_window.ppi_horizontal
			when ORIENTATION_UP		then $preferences_window.ppi_vertical
		end
	end

	def rotate(root_x, root_y, window_x, window_y)
		case @orientation
			when ORIENTATION_LEFT		# rotate to ORIENTATION_UP
				self.window.move_resize(root_x - (@breadth - window_y), root_y - window_x, @breadth, length)
				@orientation = ORIENTATION_UP

			when ORIENTATION_UP
				self.window.move_resize(root_x - window_y, root_y - (@breadth - window_x), length, @breadth)
				@orientation = ORIENTATION_LEFT
		end
		configure_orientation
	end

	###################################################################
	# Settings
	###################################################################
	def read_settings(settings)
		move( settings['ruler_x'], settings['ruler_y'] ) if settings['ruler_x']
		self.length = (settings['ruler_length'] || DEFAULT_RULER_LENGTH)
	end

	def write_settings(settings)
		settings['ruler_x'], settings['ruler_y'] = position
		settings['ruler_length'] = length
	end

private

	def configure_ppi
		@edge_size = 8
		@breadth = 35		# together with 'length', these are the two dimensions, independent of ruler rotation (whereas width=x, height=y)
	end

	def distance_from_zero(x, y)
		case @orientation
			when ORIENTATION_LEFT then x
			when ORIENTATION_UP		then y
		end
	end

	def configure_orientation		# make changes necessary for a new orientation
		case @orientation
			when ORIENTATION_LEFT
				@menu_box = Gdk::Rectangle.new(MENU_BOX_RELIEF, (@breadth / 2) - (MENU_BOX_HEIGHT / 2), MENU_BOX_WIDTH, MENU_BOX_HEIGHT)
				@near_edge, @far_edge = 3,4 # Gdk::Window::EDGE_WEST, Gdk::Window::EDGE_EAST

			when ORIENTATION_UP
				@menu_box = Gdk::Rectangle.new(MENU_BOX_RELIEF, (@breadth / 2) - (MENU_BOX_HEIGHT / 2), MENU_BOX_WIDTH, MENU_BOX_HEIGHT)
				@near_edge, @far_edge = 1, 6 # Gdk::Window::EDGE_NORTH, Gdk::Window::EDGE_SOUTH
		end
		self.set_size_request(@breadth, @breadth)
	end

	def mouse_is_in_window=(value)
		@mouse_is_in_window = value
		show_all
	end

	def grow(amount)	# can be negative
		w, h = self.size
		case @orientation
			when ORIENTATION_LEFT then resize(w + amount, h)
			when ORIENTATION_UP then resize(w, h + amount)
		end
	end

	def prepare_rotated_canvas(cr)
		case @orientation
			when ORIENTATION_UP
				cr.translate(@breadth, 0)
				cr.rotate(Math::PI / 2)
		end
	end

	def set_preferred_font(cr)
		# see $preferences_window.font => "Sans 12" by default
		font_data = $preferences_window.font.split
		font = font_data[0]
		fsize = font_data[-1].to_i
		cr.select_font_face(font,
												Cairo::FONT_SLANT_NORMAL,
												Cairo::FONT_WEIGHT_NORMAL)
		cr.set_font_size(fsize)
	end

	###################################################################
	# Drawing
	###################################################################
	def draw
		cr = @drawing_area.window.create_cairo_context
		prepare_rotated_canvas(cr)
		set_preferred_font(cr)

		# Draw Background
		cr.set_source_color($preferences_window.background_color)
		cr.rectangle(0, 0, length, @breadth)
		cr.fill

		# Draw Lines
		cr.set_source_color($preferences_window.foreground_color)
		cr.set_line_width(line_width_for_ppi)

		unit = @@unit_settings[$ruler_popup_menu.unit]

		# Two unit types require special code, as they are unrelated to inches
		case $ruler_popup_menu.unit
		when UNIT_PIXELS
			pixels_per_tick = 2
			units_per_pattern_repetition = unit.units_per_pattern_repetition
		when UNIT_PERCENTAGE
			# Change how many ticks we show, based on length of ruler
			ticks, units_per_pattern_repetition =	if length > 600 then [20, 10]
																						elsif length > 260 then [10, 20]
																						else [4, 50]
																						end
			pixels_per_tick = length.to_f / ticks.to_f
		else
			pixels_per_tick = (pixels_per_inch * unit.per_inch * unit.units_per_pattern_repetition) / unit.tick_pattern.size
			units_per_pattern_repetition = unit.units_per_pattern_repetition
		end

		# Draw top and bottom ticks and labels
		repetitions, tick_index = 0, 0
		x = pixels_per_tick
		while x < (length + OVERDRAW) do
			x = x.floor + 0.5		# Cairo likes lines in the 'center' of pixels

			tick_size = @@tick_sizes[ unit.tick_pattern[tick_index, 1].to_s ]

			# Top tick
			cr.move_to(x, 1.0)						# don't double-draw border pixel here...
			cr.line_to(x, tick_size)

			# Bottom tick
			cr.move_to(x, @breadth - tick_size)
			cr.line_to(x, @breadth - 1.0)	# ...not here either
			cr.stroke

			# Tick labels (once after each time we complete a tick_pattern)
			if tick_index == (unit.tick_pattern.size - 1)
				repetitions += 1
				text = sprintf("%d %s", repetitions * units_per_pattern_repetition,
											 (repetitions == 1) ? unit.name : '')
				w, h = 8, 12 # size of the font ?
				w *= text.length
				cr.move_to(x - (w / 2), @breadth / 2 + (h / 2))
				cr.show_text(text)
			end

			tick_index = (tick_index + 1) % unit.tick_pattern.size
			# tick_index repeats eg. 0->7 if there are 8 in the pattern

			x += pixels_per_tick
		end

		draw_mouse_tracker(cr) if @enable_mouse_tracking
		draw_menu_button(cr) if @mouse_is_in_window

		# Outline the ruler
		# cr.rectangle(0.5, 0.5, length - 1.0, @breadth - 1.0)
		# cr.stroke
	end

	def draw_mouse_tracker(cr)
		_window, mouse_x, mouse_y, key_mask = self.root_window.pointer

		set_preferred_font(cr)
		window_x, window_y = position
		# Determine what measurement to show user
		progress_pixels = distance_from_zero((mouse_x - window_x), (mouse_y - window_y))
		progress_pixels = progress_pixels.clamp(0, length)

		text = progress_pixels_to_unit_string(progress_pixels)
		# w, h = tooltip_pango_layout.pixel_size
		w, h = 8, 12 # size of the font ?
		w *= text.length

		case @orientation
		when ORIENTATION_LEFT
			tooltip_x = (mouse_x - window_x - (w / 2.0)).clamp(@menu_box.x + @menu_box.width + @menu_box.x, (length - w))
			tooltip_y = (@breadth - h) / 2.0
		when ORIENTATION_UP
			tooltip_x = (mouse_y - window_y - (w / 2.0)).clamp(@menu_box.x + @menu_box.width + @menu_box.x, (length - w))
			tooltip_y = (@breadth - h) / 2.0
		end

		# Cairo draws crisp lines when coordinates end in .5 (it's already either .0 or .5 due to division above)
		tooltip_x += 0.5 if (tooltip_x == tooltip_x.to_i)
		tooltip_y += 0.5 if (tooltip_y == tooltip_y.to_i)

		# Draw a line crossing the ruler at the measurement spot
		cr.set_source_color($preferences_window.foreground_color)
		cr.move_to(progress_pixels + 0.5, 0)
		cr.line_to(progress_pixels + 0.5, @breadth)
		cr.stroke

		# Fill a box with the background color
		cr.set_source_color($preferences_window.background_color)
		cr.rectangle(tooltip_x - 2.0, tooltip_y - 2.0, w + 4.0, h + 4.0)
		cr.fill_preserve		# (preserve so we can outline it below)

		# Draw outline around the box
		cr.set_source_color($preferences_window.foreground_color)
		cr.stroke

		# Draw measurement text
		cr.move_to(tooltip_x, tooltip_y + h - 2 )
		cr.show_text(text)
	end

	def draw_menu_button(cr)
		# Outline
		cr.set_source_color($preferences_window.background_color)
		cr.rectangle(@menu_box.x + 0.5, @menu_box.y + 0.5, @menu_box.width, @menu_box.height)
		cr.fill_preserve

		# Fill with 'horizontal' lines
		cr.set_source_color($preferences_window.foreground_color)
		y = @menu_box.y + 2.5
		while y < (@menu_box.y + @menu_box.height + -1.5) do
			cr.move_to(@menu_box.x + 2.0, y)
			cr.line_to(@menu_box.x + @menu_box.width - 1, y)
			y += 2
		end
		cr.stroke
	end

	###################################################################
	# GTK Signal Handlers
	###################################################################
	def on_button_press_event(obj, event)
		case event.event_type
		when Gdk::EventType::BUTTON_PRESS		# single-clicks
			case event.button
			when MOUSE_BUTTON_1		# popup, resize, or drag
				if menu_hit(event.x, event.y)
					$ruler_popup_menu.popup(event.x_root, event.y_root, event.x, event.y, event.time)
				elsif edge = edge_hit(event.x, event.y)
					begin_resize_drag(edge, event.button, event.x_root, event.y_root, event.time)
				else
					begin_move_drag(event.button, event.x_root, event.y_root, event.time)
				end
			when MOUSE_BUTTON_2		# middle-click = rotate ruler
				rotate(event.x_root, event.y_root, event.x, event.y)
			when MOUSE_BUTTON_3		# right-click anywhere = popup menu
				$ruler_popup_menu.popup(event.x_root, event.y_root, event.x, event.y, event.time)
			end
		when Gdk::EventType::BUTTON2_PRESS		# double-click = preferences window
			$preferences_window.present
		end
	end

	def on_enter_notify_event(obj, event)
		@mouse_is_in_window = true
		obj.queue_draw
	end

	def on_leave_notify_event(obj, event)
		@mouse_is_in_window = false
		obj.queue_draw
	end

	def on_motion_notify_event(obj, event)
		if menu_hit(event.x, event.y)
			# self.window.cursor = Gdk::Cursor.new(:hand2)
		elsif edge = edge_hit(event.x, event.y)
			#lookup = {	Gdk::Window::EDGE_NORTH => Gdk::Cursor::TOP_SIDE, Gdk::Window::EDGE_SOUTH => Gdk::Cursor::BOTTOM_SIDE,
									#						Gdk::Window::EDGE_WEST => Gdk::Cursor::LEFT_SIDE, Gdk::Window::EDGE_EAST => Gdk::Cursor::RIGHT_SIDE}
			lookup = {	1 => :top_side, 6 => :bottom_side,
									3 => :left_side, 4 => :right_side}
			# self.window.cursor = Gdk::Cursor.new(lookup[edge])
		else
			# self.window.cursor = Gdk::Cursor.new(:fleur)
		end
	end

	def on_key_press_event(obj, event)
		move_distance	= (event.state.shift_mask?) ? MOVE_LARGE : MOVE_SMALL
		grow_amount		= (event.state.shift_mask?) ? GROW_LARGE : GROW_SMALL

		if event.state.mod1_mask?		# alt key
			case event.keyval
			when Gdk::Keyval::KEY_Right, Gdk::Keyval::KEY_Down then grow(grow_amount)
			when Gdk::Keyval::KEY_Left, Gdk::Keyval::KEY_Up then grow(-grow_amount)	# shrink ;)
			else
				return false		# not handled
			end
		else
			case event.keyval
			# quick-change unit measures
			when Gdk::Keyval::KEY_1 then $ruler_popup_menu.unit = UNIT_PIXELS
			when Gdk::Keyval::KEY_2 then $ruler_popup_menu.unit = UNIT_CENTIMETERS
			when Gdk::Keyval::KEY_3 then $ruler_popup_menu.unit = UNIT_INCHES
			when Gdk::Keyval::KEY_4 then $ruler_popup_menu.unit = UNIT_PICAS
			when Gdk::Keyval::KEY_5 then $ruler_popup_menu.unit = UNIT_POINTS
			when Gdk::Keyval::KEY_6 then $ruler_popup_menu.unit = UNIT_PERCENTAGE

			# move ruler by keyboard
			when Gdk::Keyval::KEY_Left	then offset(-move_distance, 0)
			when Gdk::Keyval::KEY_Right	then offset( move_distance, 0)
			when Gdk::Keyval::KEY_Up		then offset(0, -move_distance)
			when Gdk::Keyval::KEY_Down	then offset(0,	move_distance)

			# hide ruler
			when Gdk::Keyval::KEY_Escape then Gtk.main_quit

			# show menu via keyboard
			when Gdk::Keyval::KEY_Return												# popup menu (provide "click point" in case user chooses 'rotate')
				offset_x, offset_y = @breadth / 2, @breadth / 2		# provides a visually appealing rotation
				$ruler_popup_menu.popup(self.position[0] + offset_x, self.position[1] + offset_y, offset_x, offset_y, event.time)
			else
				return false		# not handled
			end
		end
		true		# handled
	end

	###################################################################
	# Hit detection (menu button, edges)
	###################################################################
	def edge_hit(x, y)
		offset = distance_from_zero(x, y)
		if offset < @edge_size
			@near_edge
		elsif offset > (length - @edge_size)
			@far_edge
		end
	end

	def menu_hit(xc, yc, tolerance = 2)
		# check x,y with a precision +- 2px to make it easier to click on menu
		return false if xc < @menu_box.x - tolerance
		return false if yc < @menu_box.y - tolerance
		return false if xc > @menu_box.x + @menu_box.width + tolerance
		return false if yc > @menu_box.y + @menu_box.height + tolerance
		true
	end

	###################################################################
	# Utils
	###################################################################
	def line_width_for_ppi
		1.0		# TODO
	end

	def offset(x, y)
		move(position[0] + x, position[1] + y)
	end
end

# Local Variables:
# tab-width: 2
# End:
