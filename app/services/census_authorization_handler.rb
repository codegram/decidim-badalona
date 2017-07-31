# frozen_string_literal: true
# Checks the authorization against the census for Badalona.
require "digest/md5"

# This class performs a check against the official census database in order
# to verify the citizen's residence.
class CensusAuthorizationHandler < Decidim::AuthorizationHandler
  include ActionView::Helpers::SanitizeHelper

  attribute :date_of_birth, Date
  attribute :postal_code, String
  attribute :document_number, String
  attribute :document_type, Symbol

  validates :date_of_birth, presence: true
  validates :postal_code, presence: true, format: { with: /\A[0-9]*\z/ }
  validates :document_type, inclusion: { in: %i(DNI NIE PASS) }, presence: true
  validates :document_number, format: { with: /\A[A-z0-9]*\z/ }, presence: true

  validate :document_type_valid

  def self.from_params(params, additional_params = {})
    instance = super(params, additional_params)

    params_hash = hash_from(params)

    if params_hash["date_of_birth(1i)"]
      date = Date.civil(
        params["date_of_birth(1i)"].to_i,
        params["date_of_birth(2i)"].to_i,
        params["date_of_birth(3i)"].to_i
      )

      instance.date_of_birth = date
    end

    instance
  end

  # If you need to store any of the defined attributes in the authorization you
  # can do it here.
  #
  # You must return a Hash that will be serialized to the authorization when
  # it's created, and available though authorization.metadata
  def metadata
    super.merge(postal_code: postal_code)
  end

  def census_document_types
    %i(DNI NIE PASS).map do |type|
      [I18n.t(type, scope: "decidim.census_authorization_handler.document_types"), type]
    end
  end

  def unique_id
    Digest::MD5.hexdigest(
      "#{document_number}-#{Rails.application.secrets.secret_key_base}"
    )
  end

  private

  def sanitized_document_type
    case document_type&.to_sym
    when :DNI
      "01"
    when :PASS
      "02"
    when :NIE
      "03"
    end
  end

  def sanitized_date_of_birth
    @sanitized_date_of_birth ||= date_of_birth&.strftime("%Y%m%d")
  end

  def document_type_valid
    return nil if response.blank?

    errors.add(:document_number, I18n.t("census_authorization_handler.invalid_document")) unless response["status"] == "OK"
  end

  def response
    return nil if date_of_birth.blank? ||
                  postal_code.blank? ||
                  document_type.blank? ||
                  document_number.blank?

    return @response if defined?(@response)

    response ||= Faraday.get Rails.application.secrets.census_url do |request|
      request.headers["Content-Type"] = "text/json"
      request.body = request_body
    end

    @response ||= JSON.parse(response.body)
  end

  def request_body
    {
      datnaix: date_of_birth,
      cdpost: postal_code,
      tipdoc: document_type,
      docident: document_number
    }.to_json
  end
end
