require 'base64'
require 'securerandom'

class BasicAuthExampleClient < Struct.new(
        :username,
        :password
      )

  include ClientApiBuilder::Router
  include ClientApiBuilder::Section
  include ClientApiBuilder::ActiveSupportNotifications

  base_url 'https://www.example.com'

  configure_retries(2)

  header 'Authorization', :basic_authorization
  query_param('cache_buster') { (Time.now.to_f * 1000).to_i }

  route :get_apps, '/apps'
  route :get_app, '/apps/:app_id'

  section :users do
    header 'Authorization', :bearer_authorization

    route :create_user, '/users?z={cache_buster}'
  end

  def cache_buster
    (Time.now.to_f * 1000).to_i
  end

  private

  def auth_token
    @auth_token ||= SecureRandom.uuid
  end

  def basic_authorization
    'basic ' + Base64.strict_encode64(username + ':' + password)
  end

  def bearer_authorization
    'bearer ' + auth_token
  end
end
