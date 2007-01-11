class LogItem < ActiveRecord::Base
  belongs_to :person
  
  def object
    if model_name =~ /^[A-Z][a-z]{1,15}$/
      @object ||= eval(model_name).find(instance_id) rescue nil
    end
  end
  
  def object_description
    return nil unless object
    if object.respond_to?(:name)
      object.name
    else
      object.id
    end
  end
  
  def object_url
    action = 'view'
    id = instance_id
    case model_name
      when 'Event'
        controller = 'pictures'
        action = 'view_event'
      when 'Comment'
        controller = 'verses'
        id = object.verse.id
      when 'Family'
        controller = 'people'
        id = object.people.first.id
      else
        controller = model_name.pluralize.downcase
    end
    "/#{controller}/#{action}/#{id}"
  end
  
  def object_image_url
    return nil unless object.respond_to? 'has_photo?' and object.has_photo?
    controller = model_name.pluralize.downcase
    action = 'photo'
    id = "#{instance_id}.tn.jpg"
    "/#{controller}/#{action}/#{id}"
  end
  
  serialize :changes
end