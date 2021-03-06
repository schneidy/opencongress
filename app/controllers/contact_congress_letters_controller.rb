class ContactCongressLettersController < ApplicationController
  require 'yahoo_geocoder'

  before_filter :page_view, :only => :show
  
  def new
    @page_title = "Contact Congress"
    @bill = Bill.find_by_ident(params[:bill])
  

    if logged_in?
      @sens = current_user.my_sens
      @reps = current_user.my_reps
  
      if @sens.empty? && @reps.empty?
        flash[:notice] = "In order to contact your representatives in Congress, you must configure your account.  Please enter your zipcode and address in the form below."
        redirect_to user_profile
      end
    else
      @sens = @reps = []
    end
  
    if params[:position].nil?
      render 'select_position'
      return
    end
      
    formageddon_configured = false
    ### loop through recipients and see if formageddon is configured
    
    
    @position = params[:position]
  
    case @position
    when 'support'
      message_start = "I support #{@bill.typenumber} - #{@bill.title_common}, and am tracking it using OpenCongress.org, the free public resource website for government transparency and accountability."      
    when 'oppose'
      message_start = "I oppose #{@bill.typenumber} - #{@bill.title_common}, and am tracking it using OpenCongress.org, the free public resource website for government transparency and accountability."      
    else
      message_start = "I'm tracking #{@bill.typenumber} - #{@bill.title_common} using OpenCongress.org, the free public resource website for government transparency and accountability."
    end
  
    @formageddon_thread = Formageddon::FormageddonThread.new
    @formageddon_thread.prepare(:user => current_user, :subject => "#{@bill.typenumber} #{@bill.title_common}", :message => message_start)
  end

  
  def get_recipients
    @bill = Bill.find_by_ident(params[:bill])
    
    unless params[:zip4].blank?
      @sens, @reps = Person.find_current_congresspeople_by_zipcode(params[:zip5], params[:zip4])
    else
      yg = YahooGeocoder.new("#{params[:address]}, #{params[:zip5]}")
      unless yg.zip5.nil?
        @sens, @reps = Person.find_current_congresspeople_by_zipcode(yg.zip5, yg.zip4)
        @zip4 = yg.zip4
      end
      
      
      @sens, @reps = Person.find_current_congresspeople_by_address_and_zipcode(params[:address], params[:zip5])
    end

    @sens = [] unless @sens
    if @reps and @reps.size == 1
      @letter_start = "I am writing as your constituent in the #{@reps.first.district.to_i.ordinalize} Congressional district of #{State.for_abbrev(@reps.first.state)}. "
    else
      @reps = []
    end
  end
  
  def show
    @contact_congress_letter = ContactCongressLetter.find(params[:id])
    
    @page_title = "My Letter to Congress: #{@contact_congress_letter.formageddon_threads.first.formageddon_letters.first.subject}"
    @meta_description = "This is a letter to Congress sent using OpenCongress.org by user #{@contact_congress_letter.user.login} regarding #{@contact_congress_letter.bill.typenumber} #{@contact_congress_letter.bill.title_common}. OpenCongress is a free and open-source public resource website for tracking and contacting the U.S. Congress."

    if params[:print_version] == 'true'
      render :partial => 'contact_congress_letters/print', 
             :locals => { :letter => @contact_congress_letter.formageddon_threads.first.formageddon_letters.first },
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
    
    bill = Bill.find_by_ident(params[:bill])

    @letters.each do |l|  
      cclft = ContactCongressLettersFormageddonThread.find_by_formageddon_thread_id(l.formageddon_thread.id)
      if cclft.nil?
        if @contact_congress_letter.nil?
          @contact_congress_letter = ContactCongressLetter.new
          @contact_congress_letter.disposition = params[:disposition]
          @contact_congress_letter.bill = bill unless bill.nil?
          @contact_congress_letter.save
        end
        
        @contact_congress_letter.formageddon_threads << l.formageddon_thread
      else
        @contact_congress_letter = cclft.contact_congress_letter
        break
      end
    end
    
    if @contact_congress_letter.nil? 
      # something weird happened
      redirect_to '/'
      return
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
              puts("GOT GROUP!!!!!!!!!!!!!!!!! #{@group.name}")
              puts("INCLUDE BILLS?!!!!!!!!!!!!!!!!!  #{@group.bills.include?(@contact_congress_letter.bill)}")

              # make sure this group is tracking this bill and user is a member
              if @group.bills.include?(@contact_congress_letter.bill) and 
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
        @contact_congress_letter.save
      else
        @new_user_notice = false
      end
    end
    
    render :action => 'create'
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
