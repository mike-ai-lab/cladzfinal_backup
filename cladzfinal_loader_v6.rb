# CladzFinal Loader - Version 6 BACKUP

# Load V6 core module
require_relative 'cladzfinal_core_v6'

# CladzFinal Menu Module
module CladzFinalMenuModule

  def self.execute
    # Get current selection
    model = Sketchup.active_model
    selection = model.selection
    
    if selection.empty?
      UI.messagebox("Please select a face to apply the CladzFinal layout to.")
      return
    end
    
    # Find first face in selection
    face = nil
    matrix = Geom::Transformation.new
    
    selection.each do |entity|
      if entity.is_a?(Sketchup::Face)
        face = entity
        break
      end
    end
    
    unless face
      UI.messagebox("Please select a face to apply the CladzFinal layout to.")
      return
    end
    
    # Create face position object
    face_position = CladzFinalFacePosition.new
    face_position.face = face
    face_position.matrix = matrix
    
    # Display V6 dialog
    BR_CLADZFINAL.display_dialog(face_position, 0)
  end

  # Add menu items
  unless file_loaded?(__FILE__)
    
    # Add to Extensions menu
    extensions_menu = UI.menu("Extensions")
    extensions_menu.add_item("CladzFinal V6 BACKUP") { self.execute }
    
    file_loaded(__FILE__)
    puts "[CladzFinal] V6 BACKUP menu items added successfully at #{Time.now.strftime("%H:%M-%d")}"
  end

end

puts "[CladzFinal] V6 BACKUP loader completed at #{Time.now.strftime("%H:%M-%d")}"