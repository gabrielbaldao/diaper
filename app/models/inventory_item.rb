# == Schema Information
#
# Table name: inventory_items
#
#  id                  :bigint(8)        not null, primary key
#  storage_location_id :integer
#  item_id             :integer
#  quantity            :integer
#  created_at          :datetime
#  updated_at          :datetime
#

class InventoryItem < ApplicationRecord
  after_initialize :set_quantity

  belongs_to :storage_location
  belongs_to :item

  validates :quantity, presence: true
  validates :storage_location_id, presence: true
  validates :item_id, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0}

  delegate :name, to: :item, prefix: true

  def self.quantity_by_category
    self.includes(:item).select("items.category").group("items.category").sum(:quantity).sort_by { |_, v| -v }
  end

  def set_quantity
    self.quantity ||= 0
  end
end
