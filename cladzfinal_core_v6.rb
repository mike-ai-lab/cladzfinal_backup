# CladzFinal Core Module - Version 6 BACKUP
# Fixed commit system + 2000 element limit due to component performance

class CladzFinalFacePosition
  attr_accessor :face, :matrix
  def initialize
    @face = nil
    @matrix = Geom::Transformation.new
  end
end

module BR_CLADZFINAL
  
  # Layout parameters (stored in model units)
  @@length = 0.6      # Default 60cm for realistic cladding
  @@height = 0.3      # Default 30cm for realistic cladding
  @@thickness = 0.02  # Default 2cm thickness
  @@joint_length = 0.005
  @@joint_width = 0.005
  @@row_offset = 0.3
  @@color_name = "CladzFinal-V6"
  
  # Store current dialog context
  @@current_dialog = nil
  @@current_face_position = nil
  @@preview_group = nil  # Track preview group for removal
  
  def self.get_unit_conversion
    unit = Sketchup.active_model.options["UnitsOptions"]["LengthUnit"]
    # 0 = inches, 1 = feet, 2 = mm, 3 = cm, 4 = m
    conversions = [1.0, 12.0, 0.1/2.54, 1.0/2.54, 100.0/2.54]
    return conversions[unit] if unit >= 0 && unit <= 4
    1.0/2.54 # Default to cm
  end
  
  def self.get_unit_name
    unit = Sketchup.active_model.options["UnitsOptions"]["LengthUnit"]
    unit_names = ["inches", "feet", "mm", "cm", "m"]
    unit_names[unit] || "cm"
  end
  
  # Get appropriate precision for current units
  def self.get_unit_precision
    unit_name = get_unit_name
    case unit_name
    when "mm"
      0  # No decimals for mm
    when "cm"
      1  # 1 decimal for cm
    when "m"
      3  # 3 decimals for m (millimeter precision)
    when "inches"
      2  # 2 decimals for inches
    when "feet"
      3  # 3 decimals for feet
    else
      2  # Default
    end
  end
  
  def self.create_materials(color_name)
    materials_array = []
    model = Sketchup.active_model
    materials = model.materials
    
    base_material = materials[color_name]
    unless base_material
      base_material = materials.add(color_name)
      base_material.color = Sketchup::Color.new(122, 122, 122)
    end
    
    materials_array << base_material
    materials_array
  end
  
  # Create component definition for cladding element
  def self.create_cladding_component(length_su, height_su, thickness_su, material, color_name)
    model = Sketchup.active_model
    definitions = model.definitions
    
    # Create unique component name
    component_name = "CladzFinal_#{(length_su * 1000).to_i}x#{(height_su * 1000).to_i}x#{(thickness_su * 1000).to_i}_#{color_name}"
    
    # Check if component already exists
    existing_def = definitions[component_name]
    return existing_def if existing_def
    
    # Create new component definition
    component_def = definitions.add(component_name)
    
    # Create the basic face
    points = [
      Geom::Point3d.new(0, 0, 0),
      Geom::Point3d.new(length_su, 0, 0),
      Geom::Point3d.new(length_su, height_su, 0),
      Geom::Point3d.new(0, height_su, 0)
    ]
    
    face = component_def.entities.add_face(points)
    
    if face
      # Apply material
      face.material = material
      face.back_material = material
      
      # Add thickness if specified
      if thickness_su != 0
        begin
          face.pushpull(-thickness_su.abs) # Negative for inward extrusion
        rescue => e
          puts "[CladzFinal] Warning: Could not add thickness to component: #{e.message}"
        end
      end
    end
    
    puts "[CladzFinal] Created component: #{component_name}"
    return component_def
  end
  
  # Remove previous preview
  def self.remove_preview
    if @@preview_group && @@preview_group.valid?
      model = Sketchup.active_model
      model.entities.erase_entities(@@preview_group)
      puts "[CladzFinal] Previous preview removed"
    end
    @@preview_group = nil
  end
  
  # Create layout (preview=true for Gen. Preview, preview=false for Commit)
  def self.create_layout(face_position, redo_mode = 0, options = {})
    return 0 unless face_position && face_position.face
    
    is_preview = options[:preview] || false
    
    begin
      model = Sketchup.active_model
      
      if is_preview
        # For preview, don't start operation (allows easy removal)
        puts "[CladzFinal] Creating preview layout..."
        # Remove any existing preview first
        remove_preview
      else
        # For permanent, start operation
        model.start_operation("Create CladzFinal V6 Layout", true)
        puts "[CladzFinal] Creating permanent layout..."
        # Remove preview before creating permanent
        remove_preview
      end
      
      # Get unit conversion factor
      unit_conversion = get_unit_conversion
      unit_name = get_unit_name
      
      # Convert model units to SketchUp internal units (inches)
      length_su = @@length * unit_conversion
      height_su = @@height * unit_conversion
      thickness_su = @@thickness * unit_conversion
      joint_length_su = @@joint_length * unit_conversion
      joint_width_su = @@joint_width * unit_conversion
      row_offset_su = @@row_offset * unit_conversion
      
      # Realistic cladding minimum sizes
      min_element_size_model = case unit_name
      when "mm"
        50.0    # 50mm minimum
      when "cm"
        5.0     # 5cm minimum
      when "m"
        0.05    # 5cm minimum (0.05m)
      when "inches"
        2.0     # 2 inches minimum
      when "feet"
        0.17    # ~2 inches minimum
      else
        5.0     # Default 5cm
      end
      
      if @@length < min_element_size_model || @@height < min_element_size_model
        if !is_preview
          UI.messagebox(
            "⚠️ ELEMENT TOO SMALL ⚠️\n\n" +
            "Element size: #{@@length} × #{@@height} #{unit_name}\n" +
            "Minimum for cladding: #{min_element_size_model} #{unit_name}\n\n" +
            "Use larger cladding elements."
          )
          model.abort_operation
        end
        return 0
      end
      
      if length_su <= 0 || height_su <= 0
        if !is_preview
          UI.messagebox("Invalid dimensions: length and height must be positive")
          model.abort_operation
        end
        return 0
      end
      
      face = face_position.face
      face_matrix = face_position.matrix
      normal = face.normal.transform(face_matrix)
      normal.normalize!
      
      # Get face bounds
      bounds = face.bounds
      min_x = bounds.min.x
      max_x = bounds.max.x
      min_y = bounds.min.y
      max_y = bounds.max.y
      
      # PERFORMANCE CHECK (only for permanent layouts)
      face_width_su = max_x - min_x
      face_height_su = max_y - min_y
      face_area_su = face_width_su * face_height_su
      element_area_su = length_su * height_su
      
      # Convert back to model units for display
      face_width_model = face_width_su / unit_conversion
      face_height_model = face_height_su / unit_conversion
      
      if element_area_su > 0
        estimated_elements = (face_area_su / element_area_su).to_i
        
        puts "[CladzFinal] PERFORMANCE CHECK:"
        puts "  Face size: #{face_width_model.round(2)} × #{face_height_model.round(2)} #{unit_name}"
        puts "  Element size: #{@@length} × #{@@height} #{unit_name}"
        puts "  Estimated elements: #{estimated_elements}"
        
        # Only show warnings for permanent layouts, not previews
        if !is_preview && estimated_elements > 5000
          result = UI.messagebox(
            "⚠️ PERFORMANCE WARNING ⚠️\n\n" +
            "This will create approximately #{estimated_elements} elements!\n\n" +
            "This may slow down SketchUp significantly.\n\n" +
            "Continue anyway?",
            MB_YESNO
          )
          if result != 6 # Not Yes
            model.abort_operation
            return 0
          end
        elsif !is_preview && estimated_elements > 2000
          result = UI.messagebox(
            "ℹ️ Large Layout Notice\n\n" +
            "This will create approximately #{estimated_elements} elements.\n\n" +
            "Using components for optimal performance.\n\n" +
            "Continue?",
            MB_YESNO
          )
          if result != 6 # Not Yes
            model.abort_operation
            return 0
          end
        end
      end
      
      # Create materials
      materials = create_materials(@@color_name)
      material = materials.first
      
      # Create component definition for this element type
      component_def = create_cladding_component(length_su, height_su, thickness_su, material, @@color_name)
      
      # Create main group
      if is_preview
        main_group = model.entities.add_group
        main_group.name = "CladzFinal V6 Preview"
        @@preview_group = main_group  # Store reference for removal
      else
        main_group = model.entities.add_group
        main_group.name = "CladzFinal V6 Layout"
      end
      
      # Generate layout using component instances
      element_count = 0
      max_elements = 2000  # Increased limit due to component performance
      
      pos_y = min_y
      row_index = 0
      
      while pos_y < max_y && element_count < max_elements
        # Calculate row offset for staggered pattern
        current_offset = (row_index * row_offset_su) % (length_su + joint_length_su)
        pos_x = min_x + current_offset
        
        while pos_x < max_x && element_count < max_elements
          # Create component instance
          transformation = Geom::Transformation.new([pos_x, pos_y, 0])
          instance = main_group.entities.add_instance(component_def, transformation)
          
          if instance
            element_count += 1
          end
          
          pos_x += length_su + joint_length_su
        end
        
        pos_y += height_su + joint_width_su
        row_index += 1
      end
      
      if !is_preview
        model.commit_operation
        puts "[CladzFinal] V6 Permanent layout created with #{element_count} component instances at #{Time.now.strftime("%H:%M:%S")}"
        
        if element_count >= max_elements
          UI.messagebox("Layout created with #{element_count} component instances (reached limit).")
        else
          UI.messagebox("Layout committed with #{element_count} component instances!")
        end
      else
        puts "[CladzFinal] V6 Preview created with #{element_count} component instances at #{Time.now.strftime("%H:%M:%S")}"
      end
      
      return 1
      
    rescue => e
      puts "[CladzFinal] Error in create_layout: #{e.message}"
      puts e.backtrace
      if !is_preview
        model.abort_operation if model
      end
      return 0
    end
  end
  
  def self.display_dialog(face_position, redo_mode = 0)
    @@current_face_position = face_position
    
    # Create HTML dialog
    dialog_options = {
      :dialog_title => "CladzFinal V6 BACKUP - Fixed Commit System",
      :preferences_key => "CladzFinalLayout",
      :scrollable => true,
      :resizable => true,
      :width => 540,
      :height => 720,
      :left => 200,
      :top => 100,
      :min_width => 400,
      :min_height => 600,
      :style => UI::HtmlDialog::STYLE_DIALOG
    }
    
    @@current_dialog = UI::HtmlDialog.new(dialog_options)
    
    # Set dialog file
    html_path = File.join(__dir__, 'dialogs', 'CladzFinalDialog_V6.html')
    
    if File.exist?(html_path)
      @@current_dialog.set_file(html_path)
    else
      UI.messagebox("Error: Could not find CladzFinal V6 dialog file")
      return
    end
    
    # Setup callbacks
    setup_dialog_callbacks(@@current_dialog, face_position, redo_mode)
    
    # Show dialog
    @@current_dialog.show
    
    puts "[CladzFinal] V6 BACKUP Fixed Commit dialog displayed at #{Time.now.strftime("%H:%M:%S")}"
  end
  
  # Setup dialog callbacks for HTML dialog
  def self.setup_dialog_callbacks(dialog, face_position, redo_mode)
    # Get model units callback
    dialog.add_action_callback("cladzfinal_get_units") do |action_context, message|
      unit_name = get_unit_name
      puts "[CladzFinal] Sending model units to dialog: #{unit_name}"
      dialog.execute_script("setModelUnits('#{unit_name}');")
    end
    
    # Gen. Preview callback (PREVIEW ONLY)
    dialog.add_action_callback("cladzfinal_preview") do |action_context, values_json|
      puts "[CladzFinal] GEN. PREVIEW: #{values_json}"
      process_layout_with_values(values_json, face_position, redo_mode, true)  # true = preview
    end
    
    # Commit callback (PERMANENT)
    dialog.add_action_callback("cladzfinal_commit") do |action_context, values_json|
      puts "[CladzFinal] COMMIT (Permanent): #{values_json}"
      result = process_layout_with_values(values_json, face_position, redo_mode, false)  # false = permanent
      if result == 1
        dialog.close  # Close dialog after successful permanent creation
      end
    end
    
    # Close dialog callback
    dialog.add_action_callback("cladzfinal_close") do |action_context, message|
      puts "[CladzFinal] Closing dialog"
      remove_preview  # Clean up any preview when closing
      dialog.close
    end
    
    # Preset callbacks
    dialog.add_action_callback("cladzfinal_load_presets") do |action_context, message|
      load_preset_list(dialog)
    end
    
    dialog.add_action_callback("cladzfinal_load_preset") do |action_context, preset_name|
      load_preset(dialog, preset_name)
    end
    
    dialog.add_action_callback("cladzfinal_save_preset") do |action_context, values_json|
      save_preset(dialog, values_json)
    end
    
    dialog.add_action_callback("cladzfinal_delete_preset") do |action_context, preset_name|
      delete_preset(dialog, preset_name)
    end
  end
  
  # Process layout creation with values from HTML dialog
  def self.process_layout_with_values(values_json, face_position, redo_mode, is_preview = false)
    begin
      values = JSON.parse(values_json)
      puts "[CladzFinal] Processing values (preview=#{is_preview}): #{values}"
      
      # Store values directly (they're already in model units)
      @@length = values['length'].to_f
      @@height = values['height'].to_f
      @@thickness = values['thickness'].to_f
      @@joint_length = values['joint_length'].to_f
      @@joint_width = values['joint_width'].to_f
      @@row_offset = values['row_offset'].to_f
      @@color_name = values['color_name'].to_s
      
      puts "[CladzFinal] Parameters set: L=#{@@length}, H=#{@@height}, T=#{@@thickness} #{get_unit_name}"
      
      result = create_layout(face_position, redo_mode, { preview: is_preview })
      
      if result == 0
        if !is_preview
          UI.messagebox("CladzFinal layout creation failed. Please check your parameters.")
        end
      else
        if is_preview
          puts "[CladzFinal] Preview created successfully!"
        else
          puts "[CladzFinal] Permanent layout committed successfully!"
        end
      end
      
      return result
      
    rescue => e
      puts "[CladzFinal] Error processing layout values: #{e.message}"
      if !is_preview
        UI.messagebox("Error processing layout parameters: #{e.message}")
      end
      return 0
    end
  end
  
  # PRESET SYSTEM METHODS
  
  def self.get_preset_directory
    preset_dir = File.join(__dir__, 'presets_v5')  # Use V5 presets
    Dir.mkdir(preset_dir) unless File.directory?(preset_dir)
    preset_dir
  end
  
  def self.load_preset_list(dialog)
    puts "[CladzFinal] Loading V6 preset list..."
    
    dialog.execute_script("clearPresetList();")
    
    preset_dir = get_preset_directory
    
    Dir.glob(File.join(preset_dir, '*.cladzfinal')).each do |file|
      preset_name = File.basename(file, '.cladzfinal')
      puts "[CladzFinal] Found V6 preset: #{preset_name}"
      dialog.execute_script("addPresetToList('#{preset_name}');")
    end
    
    puts "[CladzFinal] V6 preset list loaded"
  end
  
  def self.load_preset(dialog, preset_name)
    puts "[CladzFinal] Auto-loading V6 preset: #{preset_name}"
    
    preset_file = File.join(get_preset_directory, "#{preset_name}.cladzfinal")
    
    unless File.exist?(preset_file)
      UI.messagebox("Preset file not found: #{preset_name}")
      return
    end
    
    begin
      values = {}
      precision = get_unit_precision
      
      File.open(preset_file, 'r').each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?('CladzFinal preset parameters')
        
        parts = line.split(';')
        next if parts.size < 2
        
        key = parts[0]
        value = parts[1].to_f
        
        case key
        when "@@length"
          values['length'] = value.round(precision)
        when "@@height"
          values['height'] = value.round(precision)
        when "@@thickness"
          values['thickness'] = value.round(precision)
        when "@@joint_length"
          values['joint_length'] = value.round(precision)
        when "@@joint_width"
          values['joint_width'] = value.round(precision)
        when "@@row_offset"
          values['row_offset'] = value.round(precision)
        when "@@color_name"
          values['color_name'] = parts[1]
        end
      end
      
      puts "[CladzFinal] V6 preset values auto-loaded: #{values}"
      
      # Send values to dialog for display
      dialog.execute_script("setPresetValues(#{values.to_json});")
      
      puts "[CladzFinal] V6 preset auto-loaded and displayed in dialog"
      
    rescue => e
      puts "[CladzFinal] Error auto-loading V6 preset: #{e.message}"
      UI.messagebox("Error loading preset: #{e.message}")
    end
  end
  
  def self.save_preset(dialog, values_json)
    begin
      values = JSON.parse(values_json)
      preset_name = values['name']
      
      puts "[CladzFinal] Saving V6 preset: #{preset_name}"
      
      # Clean preset name
      clean_name = preset_name.gsub(/[^a-zA-Z0-9_-]/, '_')
      preset_file = File.join(get_preset_directory, "V6-#{clean_name}.cladzfinal")
      
      File.open(preset_file, 'w') do |file|
        file.puts "CladzFinal preset parameters;#{preset_name};"
        file.puts "@@length;#{values['length']};"
        file.puts "@@height;#{values['height']};"
        file.puts "@@thickness;#{values['thickness']};"
        file.puts "@@joint_length;#{values['joint_length']};"
        file.puts "@@joint_width;#{values['joint_width']};"
        file.puts "@@row_offset;#{values['row_offset']};"
        file.puts "@@color_name;#{values['color_name']};"
      end
      
      puts "[CladzFinal] V6 preset saved successfully"
      
      # Reload preset list
      load_preset_list(dialog)
      
      UI.messagebox("Preset '#{preset_name}' saved successfully!")
      
    rescue => e
      puts "[CladzFinal] Error saving V6 preset: #{e.message}"
      UI.messagebox("Error saving preset: #{e.message}")
    end
  end
  
  def self.delete_preset(dialog, preset_name)
    puts "[CladzFinal] Deleting V6 preset: #{preset_name}"
    
    preset_file = File.join(get_preset_directory, "#{preset_name}.cladzfinal")
    
    unless File.exist?(preset_file)
      UI.messagebox("Preset file not found: #{preset_name}")
      return
    end
    
    begin
      File.delete(preset_file)
      puts "[CladzFinal] V6 preset deleted successfully"
      
      # Reload preset list
      load_preset_list(dialog)
      
      UI.messagebox("Preset deleted successfully!")
      
    rescue => e
      puts "[CladzFinal] Error deleting V6 preset: #{e.message}"
      UI.messagebox("Error deleting preset: #{e.message}")
    end
  end
  
end

puts "[CladzFinal] V6 BACKUP core module loaded at #{Time.now.strftime("%H:%M-%d")} - 2000 ELEMENT LIMIT!"