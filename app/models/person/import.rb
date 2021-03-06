class Person
  
  MAX_RECORDS_TO_IMPORT = 500
  
  COLUMN_ALIASES = {
    'First Name'             => 'first_name',
    'Last Name'              => 'last_name',
    'Household Name Format'  => 'family_name',
    'Gender'                 => 'gender',
    'DOB'                    => 'birthday',
    'Address1'               => 'family_address1',
    'Address 1'              => 'family_address1',
    'Address2'               => 'family_address2',
    'Address 2'              => 'family_address2',
    'City'                   => 'family_city',
    'State Province'         => 'family_state',
    'Postal Code'            => 'family_zip',
    'Home Phone'             => 'family_home_phone',
    'Work Phone'             => 'work_phone',
    'Cell Phone'             => 'mobile_phone',
    'Individual Email'       => 'email',
    'Household Email'        => 'family_email'
  }
  
  module Import
    def self.included(mod)
      mod.extend(ClassMethods)
    end

    module ClassMethods
      def importable_column_names
        (columns.map { |c| c.name } + Family.columns.map { |c| "family_#{c.name}" }).reject { |c| %w(site_id family_site_id encrypted_password salt email_changed email_bounces flags parental_consent admin_id feed_code twitter_account api_key deleted signin_count latitude longitude family_deleted).include?(c) or c =~ /_at$/ }
      end
      
      def translate_column_name(col)
        importable_column_names.include?(col) ? col : COLUMN_ALIASES[col]
      end
      
      def queue_import_from_csv_file(file, match_by_name=true, merge_attributes={})
        data = FasterCSV.parse(file)
        attributes = data.shift.map { |a| translate_column_name(a) }
        data[0...MAX_RECORDS_TO_IMPORT].map do |row|
          person, family = get_changes_for_import(attributes, row, match_by_name)
          person.attributes = merge_attributes
          if person.changed? or family.changed?
            changes = person.changes.clone
            family.changes.each { |k, v| changes['family_' + k] = v }
            [person, changes]
          else
            nil
          end
        end.compact
      end
  
      def get_changes_for_import(attributes, row, match_by_name=true)
        row_as_hash = {}
        row.each_with_index do |col, index|
          if a = attributes[index]
            row_as_hash[a] = col
          end
        end
        person_hash, family_hash = split_change_hash(row_as_hash)
        if record = tiered_find(person_hash, match_by_name)
          record.attributes = person_hash
          record.family.attributes = family_hash
          [record, record.family]
        else
          [new(person_hash), Family.new(family_hash)]
        end
      end
  
      def tiered_find(attributes, match_by_name=true)
        a = attributes.clone.reject_blanks
        a['id']        &&
          find_by_id(a['id'])               ||
        a['legacy_id'] &&
          find_by_legacy_id(a['legacy_id']) ||
        match_by_name  && a['first_name'] && a['last_name'] && a['birthday'] &&
          find_by_first_name_and_last_name_and_birthday(a['first_name'], a['last_name'], Date.parse(a['birthday'])) ||
        match_by_name  && a['first_name'] && a['last_name'] &&
          find_by_first_name_and_last_name(a['first_name'], a['last_name'])
      end
  
      def import_data(params)
        completed = []
        errored = []
        params[:new].to_a.each do |key, vals|
          Person.transaction do
            begin
              person_vals, family_vals = split_change_hash(vals)
              name = "#{person_vals['first_name']} #{person_vals['last_name']}"
              last_name = person_vals['last_name']
              if family_vals['id']
                family = Family.find_by_id(family_vals['id'])
              elsif family_vals['legacy_id']
                family = Family.find_by_legacy_id(family_vals['legacy_id'])
              end
              family ||= Family.create!({'name' => name, 'last_name' => last_name})
              family.update_attributes!(family_vals)
              person = Person.create!(person_vals.merge('family_id' => family.id))
            rescue => e
              errored << {:first_name => person_vals['first_name'], :last_name => person_vals['last_name'], :status => 'Error creating record.', :message => e.message}
              raise ActiveRecord::Rollback
            else
              completed << {:first_name => person_vals['first_name'], :last_name => person_vals['last_name'], :status => 'Record created.'}
            end
          end
        end
        params[:changes].to_a.each do |id, vals|
          Person.transaction do
            begin
              vals.cleanse('birthday', 'anniversary')
              person_vals, family_vals = split_change_hash(vals)
              person = Person.find(id)
              person.update_attributes!(person_vals)
              person.family.update_attributes!(family_vals)
            rescue => e
              errored << {:first_name => person.first_name, :last_name => person.last_name, :status => 'Error updating record.', :message => e.message}
              raise ActiveRecord::Rollback
            else
              completed << {:first_name => person.first_name, :last_name => person.last_name, :status => 'Record updated.'}
            end
          end
        end
        [completed, errored]
      end

      def split_change_hash(vals)
        person_vals = {}
        family_vals = {}
        vals.each do |key, val|
          if key =~ /^family_/
            family_vals[key.sub(/^family_/, '')] = val
          else
            person_vals[key] = val
          end
        end
        family_vals['legacy_id'] ||= person_vals['legacy_family_id']
        person_vals.reject! { |k, v| !Person.column_names.include?(k) or k =~ /^share_|_at$|wall_enabled/ }
        family_vals.reject! { |k, v| !Family.column_names.include?(k) or k =~ /^share_|_at$|wall_enabled/ }
        [person_vals, family_vals]
      end
    end
  end
end
