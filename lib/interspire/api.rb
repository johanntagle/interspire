begin
  require 'net/http'
  require 'nokogiri'
rescue LoadError
end

module Interspire
  # TODO: The methods expecting a list ID should also accept a ContactList object.
  class API

    # @param api_url [String] The XML API of your Interspire installation; ex. http://example.com/xml.php
    # @param user [String] The Interspire user's login name.
    # @param token [String] The Interspire user's API token.
    #
    # @return [Inter::API] An instance of the Interspire API for the given parameters.
    def initialize(api_url, user, token)
      @api_url = api_url
      @user    = user
      @token   = token
    end

    # @param list_id [Integer] The id of the contact list.
    # @param email [String] The subscriber's email address.
    # @param confirmed [boolean] (optional) +true+ if the subscriber should be set as confirmed; defaults to +false+.
    # @param format [String] (optional) The email format; either +html+ or +text+; defaults to +html+.
    # @param custom_fields [Hash] (optional) Any custom fields for the subscriber (e.g. {1 => 'Banana', 2 => 'Hamster'})
    #
    # @return [Integer] Returns the subscriber's ID upon success.
    def add_subscriber(list_id, email, confirmed = false, format = 'html', custom_fields = {})
      custom_fields_xml = custom_fields.map do |key, value|
        output = "<item><fieldid>#{key}</fieldid>"
        if value.is_a? Array
          value.each{|v| output << "<value>#{v}</value>"}
        else
          output << "<value>#{value}</value>"
        end
        output << "</item>"
      end.join
      
      xml = %Q[
        <xmlrequest>
          <username>#{@user}</username>
          <usertoken>#{@token}</usertoken>
          <requesttype>subscribers</requesttype>
          <requestmethod>AddSubscriberToList</requestmethod>
          <details>
            <emailaddress>#{email}</emailaddress>
            <mailinglist>#{list_id}</mailinglist>
            <format>#{format}</format>
            <confirmed>#{confirmed}</confirmed>
            <customfields>
              #{custom_fields_xml}
            </customfields>
          </details>
        </xmlrequest>
      ]

      response = get_response(xml)

      if success?(response)
        response.xpath('response/data').first.content.to_i
      else
        error!(response)
      end
    end

    # @return [boolean] Returns +true+ if the user is authenticated.
    def authenticated?
      xml = %Q[
        <xmlrequest>
          <username>#{@user}</username>
          <usertoken>#{@token}</usertoken>
          <requesttype>authentication</requesttype>
          <requestmethod>xmlapitest</requestmethod>
          <details>
          </details>
        </xmlrequest>
      ]

      response = get_response(xml)
      success?(response)
    end

    # @param list_id [Integer] The id of the contact list.
    # @param email [String] The subscriber's email address.
    #
    # @return [boolean] Returns +true+ upon success or raises an {Interspire::InterspireException} on failure.
    def delete_subscriber(list_id, email)
      xml = %Q[
        <xmlrequest>
          <username>#{@user}</username>
          <usertoken>#{@token}</usertoken>
          <requesttype>subscribers</requesttype>
          <requestmethod>DeleteSubscriber</requestmethod>
          <details>
            <list>#{list_id}</list>
            <emailaddress>#{email}</emailaddress>
          </details>
        </xmlrequest>
      ]

      response = get_response(xml)
      success?(response) ? true : error!(response)
    end

    # @return [Array] An Array of {Interspire::ContactList} objects.
    def get_lists
      xml = %Q[
        <xmlrequest>
          <username>#{@user}</username>
          <usertoken>#{@token}</usertoken>
          <requesttype>user</requesttype>
          <requestmethod>GetLists</requestmethod>
          <details>
          </details>
        </xmlrequest>
      ]

      response = get_response(xml)

      if success?(response)
        lists = []
        response.xpath('response/data/item').each do |list|
          lists << Interspire::ContactList.new({
            id: list.xpath('listid').first.content,
            name: list.xpath('name').first.content,
            subscribe_count: list.xpath('subscribecount').first.content,
            unsubscribe_count: list.xpath('unsubscribecount').first.content,
            auto_responder_count: list.xpath('autorespondercount').first.content,
          })
        end

        lists
      else
        error!(response)
      end
    end

    # @param list_id [Integer] The ID of the contact list.
    # @param email [String] The domain (including '@') of subscribers to filter by; ex. '@example.com' would only return subscribers like 'foo@example.com'; defaults to an empty String (returns all subscribers).
    #
    # @return [Hash] A Hash containing a +:count+ key and a +:subscribers+ Array with {Interspire::Subscriber} objects.
    def get_subscribers(list_id, email = '')
      xml = %Q[
        <xmlrequest>
          <username>#{@user}</username>
          <usertoken>#{@token}</usertoken>
          <requesttype>subscribers</requesttype>
          <requestmethod>GetSubscribers</requestmethod>
          <details>
            <searchinfo>
              <List>#{list_id}</List>
              <Email>#{email}</Email>
            </searchinfo>
          </details>
        </xmlrequest>
      ]

      response = get_response(xml)

      if success?(response)
        subscribers = {}
        subscribers[:count] = response.xpath('response/data/count').first.content.to_i
        subscribers[:subscribers] = []

        response.xpath('response/data').each do |data|
          data.xpath('subscriberlist/item').each do |item|
            id = item.xpath('subscriberid').first.content.to_i
            email = item.xpath('emailaddress').first.content
            subscribers[:subscribers] << Interspire::Subscriber.new(id, email)
          end
        end

        subscribers
      else
        error!(response)
      end
    end

    # @param list_id [Integer] The ID of the contact list.
    # @param email [String] The subscriber's email address.
    #
    # @return [boolean] +true+ or +false+ if the +email+ is on the given contact list.
    def in_contact_list?(list_id, email)
      response = check_contact_list(list_id, email)

      if success?(response)
        # The 'data' element will contain the subscriber ID.
        ! response.xpath('response/data').first.content.empty?
      else
        false
      end
    end

    # @param list_id [Integer] The ID of the contact list.
    # @param email [String] The subscriber's email address.
    #
    # @return [Integer] Returns the subscriber's ID upon success.
    def get_subscriber_id(list_id, email)
      response = check_contact_list(list_id, email)

      if success?(response)
        response.xpath('response/data').first.content.to_i
      else
        error!(response)
      end
    end

    # This is an undocumented API function.  Refer to the 'xml_updatesubscriber.php' attachment
    # on this page: https://www.interspire.com/support/kb/questions/1217/Email+Marketer+XML+API+usage+and+examples
    #
    # @param subscriber_id [Integer] The ID of the subscriber.
    # @param field_id [Integer] The ID of the custom field
    # @param data [String] The data of the field
    #
    # @return [boolean] Returns +true+ if the field was updated.
    def update_subscriber_custom_field(subscriber_id, field_id, data)
      xml = %Q[
        <xmlrequest>
          <username>#{@user}</username>
          <usertoken>#{@token}</usertoken>
          <requesttype>subscribers</requesttype>
          <requestmethod>SaveSubscriberCustomField</requestmethod>
          <details>
            <subscriberids>
              <id>#{subscriber_id}</id>
            </subscriberids>
            <fieldid>#{field_id}</fieldid>
            <data>#{data}</data>
          </details>
        </xmlrequest>
      ]

      response = get_response(xml)
      success?(response)
    end


    private

    # @param xml [String] A String containing the XML request.
    #
    # @return [Nokogiri::Document] A +Nokogiri::Document+ build from the API response.
    def get_response(xml)
      url = URI.parse(@api_url)
      request = Net::HTTP::Post.new(url.path)
      request.body = xml

      response = Net::HTTP.new(url.host, url.port).start { |http| http.request(request) }

      Nokogiri::XML.parse(response.body)
    end

    # @param response [Nokogiri::Document] A +Nokogiri::Document+ parsed from the API response.
    #
    # @return [boolean] +true+ or +false+ if the +response+ was a success.
    def success?(response)
      response.xpath('response/status').first.content == 'SUCCESS'
    end

    # Raises an {Interspire::InterspireException} with details from the API +response+.
    #
    # @param response [Nokogiri::Document] A +Nokogiri::Document+ parsed from the API response.
    def error!(response)
      type  = response.xpath('response/status').first.content
      error = response.xpath('response/errormessage').first.content
      raise InterspireException, "#{type}: #{error.empty? ? 'No error message given.' : error}"
    end

    def check_contact_list(list_id, email)
      xml = %Q[
        <xmlrequest>
          <username>#{@user}</username>
          <usertoken>#{@token}</usertoken>
          <requesttype>subscribers</requesttype>
          <requestmethod>IsSubscriberOnList</requestmethod>
          <details>
            <emailaddress>#{email}</emailaddress>
            <listids>#{list_id}</listids>
          </details>
        </xmlrequest>
      ]

      get_response(xml)
    end

  end
end
