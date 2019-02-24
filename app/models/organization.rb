# == Schema Information
#
# Table name: organizations
#
#  id                 :integer          not null, primary key
#  name               :string
#  short_name         :string
#  email              :string
#  url                :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  intake_location    :integer
#  street             :string
#  city               :string
#  state              :string
#  zipcode            :string
#  latitude           :float
#  longitude          :float
#  default_email_text :text
#

class Organization < ApplicationRecord
  DIAPER_APP_LOGO = Rails.root.join("public", "img", "diaperbase-logo-full.png")

  validates :name, presence: true
  validates :short_name, presence: true, format: /\A[a-z0-9_]+\z/i
  validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp, message: "it should look like 'http://www.example.com'" }, allow_blank: true
  validates :email, format: /[^@]+@[^@]+/, allow_blank: true
  validate :correct_logo_mime_type

  has_many :adjustments, dependent: :destroy
  has_many :barcode_items, dependent: :destroy do
    def all
      unscope(where: :organization_id).where("barcode_items.organization_id = ? OR barcode_items.global = ?", proxy_association.owner.id, true)
    end
  end
  has_many :distributions, dependent: :destroy
  has_many :donations, dependent: :destroy
  has_many :purchases, dependent: :destroy
  has_many :donation_sites, dependent: :destroy
  has_many :diaper_drive_participants, dependent: :destroy
  has_many :storage_locations, dependent: :destroy
  has_many :inventory_items, through: :storage_locations
  has_many :items, dependent: :destroy
  has_many :partners, dependent: :destroy
  has_many :transfers, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :requests, dependent: :destroy
  has_many :audits, dependent: :destroy

  has_rich_text :default_email_text

  has_one_attached :logo

  accepts_nested_attributes_for :users

  geocoded_by :address
  after_validation :geocode, if: ->(obj) { obj.address.present? && obj.address_changed? }

  # NOTE: when finding Organizations, use Organization.find_by(short_name: params[:organization_id])
  def to_param
    short_name
  end

  def display_users
    users.map(&:email).join(", ")
  end

  def ordered_requests
    requests.order(status: :asc, updated_at: :desc)
  end

  def quantity_categories
    storage_locations.map(&:inventory_items).flatten.reject { |i| i.item.nil? }.group_by { |i| i.item.category }
                     .map { |i| [i[0], i[1].map(&:quantity).sum] }.sort_by { |_, v| -v }
  end

  def upcoming_distributions
    distributions&.this_week&.count || 0
  end

  # Computes full address string based on street, city, state, and zip, adding ', ' and ' ' separators
  def address
    state_and_zip = [state, zipcode].select(&:present?).join(' ')
    [street, city, state_and_zip].select(&:present?).join(', ')
  end

  def address_changed?
    street_changed? || city_changed? || state_changed? || zipcode_changed?
  end

  def address_inline
    address.split("\n").map(&:strip).join(", ")
  end

  def total_inventory
    inventory_items.sum(:quantity) || 0
  end

  def scale_values
    {
      pu_2t_3t: items.find_by(name: "Kids Pull-Ups (2T-3T)").id,
      pu_3t_4t: items.find_by(name: "Kids Pull-Ups (3T-4T)").id,
      pu_4t_5t: items.find_by(name: "Kids Pull-Ups (4T-5T)").id,
      k_preemie: items.find_by(name: "Kids (Preemie)").id,
      k_newborm: items.find_by(name: "Kids (Newborn)").id,
      k_size1: items.find_by(name: "Kids (Size 1)").id,
      k_size2: items.find_by(name: "Kids (Size 2)").id,
      k_size3: items.find_by(name: "Kids (Size 3)").id,
      k_size4: items.find_by(name: "Kids (Size 4)").id,
      k_size5: items.find_by(name: "Kids (Size 5)").id,
      k_size6: items.find_by(name: "Kids (Size 6)").id
    }
  end

  def self.seed_items(org)
    Rails.logger.info "Seeding #{org.name}'s items..."
    org_id = org.id
    canonical_items = CanonicalItem.pluck(:partner_key, :name, :category).collect { |c| { partner_key: c[0], name: c[1], category: c[2], organization_id: org_id } }
    Item.create(canonical_items)
    org.reload
  end

  def logo_path
    if logo.attached?
      ActiveStorage::Blob.service.send(:path_for, logo.key).to_s
    else
      Organization::DIAPER_APP_LOGO.to_s
    end
  end

  def valid_items
    items.map(&:partner_key)
  end

  private

  def correct_logo_mime_type
    if logo.attached? && !logo.content_type
                              .in?(%w(image/jpeg image/jpg image/pjpeg image/png image/x-png))
      logo.purge
      errors.add(:logo, "Must be a JPG or a PNG file")
    end
  end
end
