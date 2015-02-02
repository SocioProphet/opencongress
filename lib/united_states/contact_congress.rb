require 'yaml'
require 'o_c_logger'

module UnitedStates
  module ContactCongress
    extend self

    class UnmappedField < StandardError
    end

    SUPPORT_PATH = File.join Settings.data_path, "contact-congress", "support"
    CONSTANTS_PATH = File.join SUPPORT_PATH, "constants.yaml"
    VARIABLES_PATH = File.join SUPPORT_PATH, "variables.yaml"
    RECAPTCHA_PATH = File.join SUPPORT_PATH, "recaptcha-noscript.yaml"

    def constants
      @@constants ||= YAML.load(File.read(CONSTANTS_PATH))
    end

    def recaptcha_steps
      @@recaptcha_steps ||=YAML.load(File.read(RECAPTCHA_PATH))['steps']
    end

    def get_field_value(name, opts={})
      @@variables ||= {
        '$NAME_PREFIX' => 'title',
        '$NAME_FIRST' =>  'first_name',
        '$NAME_LAST' =>   'last_name',
        '$ADDRESS_STREET' => 'address1',
        '$ADDRESS_STREET_2' => 'address2',
        '$ADDRESS_CITY' => 'city',
        '$ADDRESS_STATE' => 'state',
        '$ADDRESS_STATE_POSTAL_ABBREV' => 'state',
        '$ADDRESS_ZIP5' => 'zip5',
        '$ADDRESS_ZIP4' => 'zip4',
        '$PHONE' => 'phone',
        '$EMAIL' => 'email',
        '$TOPIC' => 'issue_area',
        '$SUBJECT' => 'subject',
        '$MESSAGE' => 'message',
        '$CAPTCHA_SOLUTION' => 'captcha_solution'
      }
      val = @@variables[name] || name
      if val =~ /^\$/ && !opts[:required]
        val = 'leave_blank'
      elsif val =~ /^\$/
        raise UnmappedField, "#{name} has no mapping" if (opts[:required] && val == 'leave_blank')
      end
      val
    end

    # Returns a contact steps hash from a file path
    #
    # @param path [String] path to YAML file
    # @return [Hash,nil] Hash if successfully reading YAML file, nil otherwise
    def parse_contact_file(path)
      begin
        decode_contact_hash(YAML.load(File.read(path)))
      rescue
        puts "No YAML file found at #{path}"
        nil
      end
    end

    # Returns a decoded contact steps hash, muxing a raw contact_file hash
    # with the constants defined in the unitedstates/contact_congress repo's support folder
    def decode_contact_hash(hsh)
      hsh['contact_form']['steps'].each do |step|
        step.to_enum.each do |action, items|
          if items.is_a? Array
            items.each do |item|
              item.to_enum.each do |property, value|
                if is_const?(value)
                  item[property] = constants[value]['value'] rescue value
                end
              end
            end
          end
        end
      end
      hsh
    end

    # Sets up a person's Formageddon contact environment
    #
    # @note https://github.com/unitedstates/contact-congress/blob/master/documentation/schema.md
    # @param person [Person] person instance
    # @param path [String] path to YAML file defining contact steps
    # @return [Person, Exception] saved person instance or an exception
    def import_contact_steps_for(person, path=nil)
      OCLogger.log("Updating steps for #{person.bioguideid}...")
      path = File.join(Settings.contact_congress_path, 'members', "#{person.bioguideid}.yaml") if path.nil?
      hsh = parse_contact_file(path)
      return false if hsh.nil?
      current_step = nil  # formageddon steps can span multiple directives here, ex. 'fill_in', 'select' and 'click_on'. This acts as a cursor.
      person.formageddon_contact_steps.destroy_all
      steps = hsh['contact_form']['steps']
      steps.each do |step|

        step.each do |action, values|
          next if ['find','wait'].include? action # ignore find for now

          unless ['visit'].include? action

            # Build a step if it doesn't already exist
            person.formageddon_contact_steps << (current_step = Formageddon::FormageddonContactStep.new(
                :command => 'submit_form'
            )) if current_step.nil?

            # Build a form if the step doesn't have one, because this is a submit_form step
            current_step.formageddon_form = Formageddon::FormageddonForm.new(
                :use_field_names => true,
                :success_string => (hsh['contact_form']['success']['body']['contains'] rescue 'Thank you')
            ) if current_step.formageddon_form.nil?

          end

          # These steps get grouped together as 'submit_form' in formageddon
          if ['fill_in', 'select', 'check', 'uncheck', 'choose'].include? action

            # Map the field values for each item in the step and add a field instance to the form
            form = current_step.formageddon_form
            values.each do |item|
              # Special case if this is a captcha field.
              if item['value'] == "$CAPTCHA_SOLUTION"
                # Even more special is recaptcha. Recaptcha noscripts an iframe which must be separately fetched
                # and stored as a separate browser. If this fails then sending by webform will fail. 
                # Hopefully there is a fax number!
                if item['name'] =~ /recaptcha/
                  generate_recaptcha_form(person, form, item)
                end
                form.formageddon_form_captcha_image = Formageddon::FormageddonFormCaptchaImage.new(
                  :css_selector => item['captcha_selector']
                )
              end

              if action == "check"
                # Set the value from the YAML if this is a checkbox
                value = item['value']
              else
                # Otherwise resolve it through our variable map
                value = get_field_value(item['value'], :required => item['required'])
              end

              # Append the field to the form
              form.formageddon_form_fields << Formageddon::FormageddonFormField.new(
                :name => item['name'],
                :css_selector => item['selector'],
                :required => item['required'] || false,
                :value => value
              )
              # Email fields might have a 'disallow_plus' parameter, if the plus hack will trigger the form to fail.
              # In these cases set a flag on the form
              form.use_real_email_address = true if item['value'] == '$EMAIL' && item['disallow_plus']
            end

          # Remaining steps are either the initial visiting of a page, or no-ops.
          # TODO: Deal with CAPTCHAs
          else
            # Add the button selector to the form if this is a click on step.
            if action == 'click_on'
              if current_step.present? && current_step.formageddon_form.present?
                current_step.formageddon_form.submit_css_selector = values.first['selector']
                current_step.formageddon_form.save!
              end
            end
            # If there's a step open and we've gotten here, we're done collecting
            # fields to fill out and it's time to save and assign it.
            unless current_step.nil?
              current_step.save!
              person.formageddon_contact_steps << current_step
              current_step = nil
            end

            # 'Visit' steps get their own formageddon step
            if action == 'visit'
              step = Formageddon::FormageddonContactStep.new(:command => "visit::#{values}")
              person.formageddon_contact_steps << step
            end
          end
        end
      end
      person.save!
    end

    protected

    def generate_recaptcha_form(person, form, item)
      browser = Mechanize.new
      url = person.formageddon_contact_steps.select{|step| step.command =~ /^visit/ }.first.command.split('::').last
      browser.get(url)

      # try multiple ways to obtain the recaptcha image
      ["iframe[src*='google.com/recaptcha']", "img[src*='google.com/recaptcha']"].each do|target|
        begin
          captcha_url = browser.page.search(target).first.attr('src')
        rescue
          puts "Captcha can't be found with #{target}"
        end
        break if defined? captcha_url
      end

      # we need a captcha_url at this point ... if we don't then something went wrong (javascript >_<)
      if defined? captcha_url
        step = recaptcha_steps[1]['fill_in'][0]
        form.formageddon_recaptcha_form = Formageddon::FormageddonRecaptchaForm.new(
            :url => captcha_url,
            :response_field_css_selector => step['selector'],
            :image_css_selector => step['captcha_selector'],
            :id_selector => step['captcha_id_selector']
        )
      end

    end

    def is_const?(str)
      !! (str =~ /\A[A-Z][A-Z0-9_]*\Z/i)
    end

    def is_var?(str)
      !! (str =~ /\A\$[A-Z][A-Z0-9_]*\Z/i)
    end
  end
  
end
