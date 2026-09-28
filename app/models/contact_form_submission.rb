class ContactFormSubmission < ApplicationRecord
  STATUSES = %w[received read responded].freeze

  belongs_to :admin_user, optional: true

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 150 }
  validates :phone, length: { maximum: 20 }, allow_blank: true
  validates :subject, presence: true, length: { maximum: 200 }
  validates :message, presence: true, length: { maximum: 5000 }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :unread, -> { where(status: %w(received)) }
  scope :responded, -> { where(status: 'responded') }

  after_create :send_confirmation_email

  STATUSES.each do |value|
    define_method(:"#{value}?") { status == value }
  end

  private

  def send_confirmation_email
    ContactMailer.contact_form_received(self).deliver_later
  end
end
