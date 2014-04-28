class ContactCongressLettersController < ApplicationController

  before_filter :page_view, :only => :show
  # before_filter :warn_geocode, :only => :new

  SUCCESS_PATTERN = /SENT/
  FAILURE_PATTERN = /SENT_AS_FAX|ERROR/
  UNKNOWN_PATTERN = /WARNING|START|CAPTCHA_REQUIRED/

  def new
    @page_title = "Contact Congress"

    if !params[:bill].blank?
      @bill = Bill.find_by_ident(params[:bill])
    elsif !params[:issue].blank?
      @issue = Subject.find_by_id(params[:issue])
    end


    if logged_in?
      @sens = current_user.my_sens
      @reps = current_user.my_reps

      if @sens.empty? && @reps.empty?
        flash[:notice] = "In order to contact your representatives in Congress, you must configure your account.  Please enter your zipcode and address in the form below."
        redirect_to edit_profile_path(:login => current_user.login)
      end
    else
      @sens = @reps = []
    end

    @member_osids = (@sens + @reps).map(&:osid).select{|osid| not osid.nil?}

    if @bill and params[:position].nil?
      render 'select_position'
      return
    end

    formageddon_configured = false
    ### loop through recipients and see if formageddon is configured


    if @bill
      if @bill.talking_points.where("talking_points.include_in_message_body='t'").any?
        message_start = ""
        @bill.talking_points.where("talking_points.include_in_message_body='t'").order("talking_points.created_at ASC").each do |tp|
          message_start += "#{tp.talking_point}\n\n"
        end
      else
        @position = params[:position]

        case @position
        when 'support'
          message_start = "I support #{@bill.typenumber} - #{@bill.title_common}, and am tracking it using OpenCongress.org, the free public resource website for government transparency and accountability."
        when 'oppose'
          message_start = "I oppose #{@bill.typenumber} - #{@bill.title_common}, and am tracking it using OpenCongress.org, the free public resource website for government transparency and accountability."
        else
          message_start = "I'm tracking #{@bill.typenumber} - #{@bill.title_common} using OpenCongress.org, the free public resource website for government transparency and accountability."
        end
      end

      @subject = "#{@bill.typenumber} #{@bill.title_common}"
      @contactable_query = "contactable_type=Bill&contactable_id=#{@bill.id}"
    elsif @issue
      if @issue.talking_points.where("talking_points.include_in_message_body='t'").any?
        message_start = ""
        @issue.talking_points.where("talking_points.include_in_message_body='t'").order("talking_points.created_at ASC").each do |tp|
          message_start += "#{tp.talking_point}\n\n"
        end
      else
        message_start = "I am tracking legislation in the issue area of #{@issue.term} using OpenCongress.org, the free public resource website for government transparency and accountability."
      end
      @subject = @issue.term
      @contactable_query = "contactable_type=Subject&contactable_id=#{@issue.id}"
    end


    @formageddon_thread = Formageddon::FormageddonThread.new
    @formageddon_thread.prepare(:user => current_user, :subject => @subject, :message => message_start)
  end


  def get_recipients
    if !params[:bill].blank?
      @bill = Bill.find_by_ident(params[:bill])
    elsif !params[:issue].blank?
      @issue = Subject.find_by_id(params[:issue])
    end

    if params[:address].present?
      @sens, @reps = Person.find_current_congresspeople_by_address(params[:address])
    else
      @sens = []
      @reps = []
    end

    @sens = [] unless (@sens and @sens.length <= 2)

    if @reps and @reps.size == 1
      @letter_start = "I am writing as your constituent in the #{@reps.first.district.to_i.ordinalize} Congressional district of #{State.for_abbrev(@reps.first.state)}. "
      @letter_pat = "I am writing as your constituent in the [0-9sthnrd]+ Congressional district of [a-zA-Z ]+. ?"
    else
      @reps = []
    end
    @member_osids = (@sens + @reps).map(&:osid).select{|osid| not osid.nil?}
  end

  def show
    @contact_congress_letter = ContactCongressLetter.find(params[:id])

    if @contact_congress_letter.formageddon_threads.first.privacy =~ /PRIVATE/
      if current_user == :false or current_user != @contact_congress_letter.user
        redirect_to '/', :notice => 'You do not have permission to read that letter!'
        return
      end
    end

    @additional_letters = []
    @contact_congress_letter.formageddon_threads.each do |t|
      if t.formageddon_letters.size > 1
        @additional_letters << t.formageddon_letters[1..-1]
      end
    end
    @additional_letters.flatten!.sort!{|a,b| a.created_at <=> b.created_at } unless @additional_letters.empty?

    @page_title = "My Letter to Congress: #{@contact_congress_letter.formageddon_threads.first.formageddon_letters.first.subject}"

    if @contact_congress_letter.contactable_type == 'Bill'
      regarding = "#{@contact_congress_letter.contactable.typenumber} #{@contact_congress_letter.contactable.title_common}"
    elsif @contact_congress_letter.contactable_type == 'Subject'
      regarding = @contact_congress_letter.contactable.term
    end

    @meta_description = "This is a letter to Congress sent using OpenCongress.org by user #{@contact_congress_letter.user.login} regarding #{regarding}. OpenCongress is a free and open-source public resource website for tracking and contacting the U.S. Congress."

    if params[:print_version] == 'true'
      render :partial => 'contact_congress_letters/print',
             :locals => { :letter => @contact_congress_letter.formageddon_threads[params[:letter].to_i].formageddon_letters.first },
             :layout => false
      return
    end
  end

  def create_from_formageddon
    ## dont forget to check privacy settings
    @page_title = 'Contact Congress'

    unless params[:letter_ids].blank?
      letter_ids = params[:letter_ids].split(/,/)
      @letters = Formageddon::FormageddonLetter.find(letter_ids)
    end

    contactable = Object.const_get(params[:contactable_type]).find_by_id(params[:contactable_id])

    @letters.each do |l|
      cclft = ContactCongressLettersFormageddonThread.find_by_formageddon_thread_id(l.formageddon_thread.id)
      if cclft.nil?
        if @contact_congress_letter.nil?
          @contact_congress_letter = ContactCongressLetter.new
          @contact_congress_letter.disposition = params[:disposition]
          @contact_congress_letter.contactable = contactable unless contactable.nil?
          @contact_congress_letter.save
        end

        @contact_congress_letter.formageddon_threads << l.formageddon_thread
      else
        @contact_congress_letter = cclft.contact_congress_letter

        if current_user == :false or @letters.first.formageddon_thread.formageddon_sender_id != current_user.id
          redirect_to @contact_congress_letter
          return
        end

        break
      end
    end

    if @contact_congress_letter.nil?
      # something weird happened
      render_404 and return
    else
      if @contact_congress_letter.user.nil?
        if current_user == :false
          user = create_new_user_from_formageddon_thread(@contact_congress_letter.formageddon_threads.first)
          @contact_congress_letter.user = user
          @new_user_notice = true
        else
          @contact_congress_letter.user = current_user
          @new_user_notice = false

          # check for group
          unless params[:group_id].blank?
            @group = Group.find_by_id(params[:group_id])
            if @group
              # make sure this group is tracking this bill and user is a member
              if @group.bills.include?(@contact_congress_letter.contactable) and
                 (@group.is_member?(@contact_congress_letter.user) or @group.is_owner?(@contact_congress_letter.user))

                notebook = PoliticalNotebook.find_or_create_from_group(@group)

                notebook_item = notebook.notebook_links.create
                notebook_item.notebookable = @contact_congress_letter
                notebook_item.init_from_notebookable(@contact_congress_letter)
                notebook_item.group_user = @contact_congress_letter.user

                notebook_item.save
              else
                @group = nil
              end
            end
          end
        end
        @contact_congress_letter.is_public = (@contact_congress_letter.formageddon_threads.first.privacy == 'PUBLIC')
        @contact_congress_letter.save
      else
        @new_user_notice = false
      end
    end

    render :action => 'create'
  end

  def delayed_send
    formageddon_params = session[:formageddon_params]

    threads = session[:formageddon_unsent_threads].map{ |t| Formageddon::FormageddonThread.find(t) }
    threads.each do |t|
      t.formageddon_sender = current_user

      t.formageddon_letters.first.update_attribute(:status, 'START')
      t.formageddon_letters.first.update_attribute(:direction, 'TO_RECIPIENT')

      t.save

      if defined? Delayed
        t.formageddon_letters.first.delay.send_letter
      else
        t.formageddon_letters.first.send_letter
      end
    end

    @letter_ids = threads.collect{|t| t.formageddon_letters.first.id}.join(',')

    session[:formageddon_after_send_url] = "#{formageddon_params[:after_send_url]}&letter_ids=#{@letter_ids}" unless formageddon_params[:after_send_url].blank?
    session[:formageddon_params] = nil
    session[:formageddon_unsent_threads] = nil
  end

  def update
    @contact_congress_letter = ContactCongressLetter.find(params[:id])

    if @contact_congress_letter and @contact_congress_letter.user == current_user
      @contact_congress_letter.receive_replies = (params[:receive_replies] == 'true') if params[:receive_replies]
      if params[:privacy]
        @contact_congress_letter.formageddon_threads.each do |t|
          t.privacy = (params[:privacy] == 'PUBLIC') ? 'PUBLIC' : 'PRIVATE'

          # the following is for any letters that were saved before phone number became required
          t.sender_phone = 'None' if t.sender_phone.blank?

          t.save
        end
        @contact_congress_letter.is_public = (params[:privacy] == 'PUBLIC')
      end

      @contact_congress_letter.save
    end

    redirect_to @contact_congress_letter, :notice => "Letter setting has been updated."
  end

  def get_replies
    if params[:formageddon_get_replies_key] and params[:formageddon_get_replies_key] == ApiKeys.formageddon_get_replies_key
      emails_received = 0
      notifications_sent = 0

      Formageddon::IncomingEmailFetcher.fetch do |letter|
        cclft = ContactCongressLettersFormageddonThread.where(["formageddon_thread_id=?", letter.formageddon_thread.id]).first

        emails_received += 1

        if cclft && cclft.contact_congress_letter.receive_replies? && (letter.subject =~ /E\-News/) != 0
          notifications_sent += 1
          Rails.logger.info "Sending an email notification to: #{cclft.contact_congress_letter.user.email}"
          ContactCongressMailer.reply_received_email(cclft.contact_congress_letter, letter.formageddon_thread).deliver
        end
      end

      render :text => "#{emails_received} emails, #{notifications_sent} notifications"
    else
      render :text => "Access denied."
    end
  end

  def last
    @person = Person.find_by_bioguideid(params[:id])
    render_404 and return unless @person.present?
    last_status = @person.formageddon_threads.first.formageddon_letters.first.status rescue nil
    if (last_status =~ FAILURE_PATTERN).present?
      img = 'fail.png'
    elsif (last_status =~ SUCCESS_PATTERN).present?
      img = 'success.png'
    elsif (last_status =~ UNKNOWN_PATTERN).present?
      img = 'unknown.png'
    else
      img = 'not_tried.png'
    end

    respond_to do |format|
      format.png {send_file "#{Rails.root}/public/images/contact-congress/#{img}", :type => 'image/png', :disposition => 'inline'}
      format.text {render :text => last_status}
    end
  end

  private

  def create_new_user_from_formageddon_thread(thread)
    return nil
  end

  def page_view
    if @letter = ContactCongressLetter.find(params[:id])
      key = "page_view_ip:ContactCongressLetter:#{@letter.id}:#{request.remote_ip}"
      unless read_fragment(key)
        #@letter.increment!(:page_views_count)
        @letter.page_view
        write_fragment(key, "c", :expires_in => 1.hour)
      end
    end
  end
end
