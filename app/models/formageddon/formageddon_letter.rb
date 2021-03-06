# == Schema Information
#
# Table name: formageddon_letters
#
#  id                    :integer          not null, primary key
#  formageddon_thread_id :integer
#  direction             :string(255)
#  status                :text
#  issue_area            :string(255)
#  subject               :text
#  message               :text
#  created_at            :datetime
#  updated_at            :datetime
#  fax_id                :integer
#

# FIXME: This is ugly.
require_dependency File.expand_path(
  'app/models/formageddon/formageddon_letter',
  ActiveSupport::Dependencies.plugins_loader.plugin_paths.select{|p| p =~ /formageddon(-[0-9a-f]+)?$/}.first)

require_dependency 'renders_templates'

class Formageddon::FormageddonLetter
  ##
  # This is a monkeypatch to add faxing capability to formageddon letters
  #
  include RendersTemplates
  include Faxable
  include ContactCongressLettersHelper

  delegate :formageddon_recipient_id,:to => 'Formageddon::FormageddonThread'

  PRINT_TEMPLATE = "contact_congress_letters/print"

  def send_letter(options = {})
    recipient = formageddon_thread.formageddon_recipient

    if !recipient.contactable? #shut it down
      self.status = 'ERROR: noncontactable recipient'
      OCLogger.log("#{self.status} -- Formageddon::FormageddonThread.find(#{formageddon_thread.id})")
      ContactCongressMailer.will_not_send_email({
          :uncontactable_official => recipient,
          :message_body => self.message,
          :recipient_email => self.formageddon_thread.sender_email
        }).deliver
      Raven.capture_message "sent #{self.formageddon_thread.sender_email} a message about uncontactable recipient #{recipient.name}"
      return false
    end

    if recipient.nil? or recipient.formageddon_contact_steps.empty?
      unless status =~ /^(SENT|RECEIVED|ERROR)/  # These statuses don't depend on a proper set of contact steps
        self.status = 'ERROR: Recipient not configured for message delivery!'
        self.save
        OCLogger.log("#{self.status} -- Formageddon::FormageddonThread.find(#{formageddon_thread.id})")
      end
      return false if recipient.nil?
    end
    
   options = [{user_agent_alias: 'Windows IE 7',follow_meta_refresh: true },
              {user_agent_alias: 'Windows IE 7',follow_meta_refresh: false }]

    options.each.with_index(1) do |opts, index|
      
      # try different mechanize configurations
      browser = Mechanize.new {|config| opts.each {|k,v| config.send(k.to_s + '=',v) } }

      # execute steps for delivery attempts based on status of letter
      case status
        when 'START', 'RETRY'
          steps = recipient.execute_contact_steps(browser, self)
        when 'TRYING_CAPTCHA', 'RETRY_STEP'
          attempt = formageddon_delivery_attempts.last

          if status == 'TRYING_CAPTCHA' and ! %w(CAPTCHA_REQUIRED CAPTCHA_WRONG).include? attempt.result
            # weird state, abort
            return false
          end

          browser = (attempt.result == 'CAPTCHA_WRONG') ? attempt.rebuild_browser(browser, "after") : attempt.rebuild_browser(browser, "before")

          if options[:captcha_solution]
            @captcha_solution = options[:captcha_solution]
          end

          steps = recipient.execute_contact_steps(browser, self, attempt.letter_contact_step)
      end

      # reload this letter and return the steps if they were successful
      self.reload
      if self.status == 'SENT'
        return steps
      elsif self.status =~ /(.*ERROR.*|.*WARNING.*)/ and not index == options.size
        self.status = 'RETRY'
      end

    end

    # fall back effort if everything else fails
    if recipient.fax.present?
      send_fax :error_msg => status
    else
      steps if defined? steps
    end

  end
   
  def send_fax(options={})
    recipient = options.fetch(:recipient, formageddon_thread.formageddon_recipient)
    if recipient.fax.present?
      if defined? Settings.force_fax_recipient
        send_as_fax(Settings.force_fax_recipient)
      else
        send_as_fax(recipient.fax)
      end
      self.status = "SENT_AS_FAX"
      self.status += ": Error was, #{options[:error_msg]}" if options[:error_msg].present?
      self.save!
      return @fax # @fax _should_ be an HTTParty object with a success boolean 
    else
      return false
    end
  end

  def as_html
    @rendered ||= render_to_string(:partial => PRINT_TEMPLATE, :locals => { :letter => self })
  end

  def sender_full_name
    return "#{formageddon_thread.sender_first_name} #{formageddon_thread.sender_last_name}"
  end

  ##
  # Returns the the letter message and stripping away any PII using a regexp.
  # This mmethod is necessary because the contact information for a sender may differ
  # from the user's account information.
  #
  # @return {String} message without any PII
  #
  def message_no_pii
    return strip_pii_from_message(self.formageddon_thread, self.message)
  end

end
