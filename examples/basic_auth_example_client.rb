require 'base64'

class BasicAuthExampleClient < Struct.new(
        :username,
        :password
      )

  include ClientApiBuilder::Router

  base_url 'https://www.example.com'

  header 'Authorization', :basic_authorization
  query_param('cache_buster') { (Time.now.to_f * 1000).to_i }

  route :get_apps, '/apps'
  route :get_app, '/apps/:app_id'

  private

  def basic_authorization
    'basic ' + Base64.strict_encode64(username + ':' + password)
  end
end
