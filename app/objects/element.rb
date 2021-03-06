# Element
# =======
# Basic type of data unit, aka *Model*
# Simple as possible, holds characteristic properties of an Atom
#
# Properties
# ==========
# -- id: UUID, Uniq ID of an Element Object, Primary Key
# -- meta: JSON, holds data model information of an Atom Object
# --- name, String, name of the element
# --- group, String, *optional, plural name of the element, autogenerating if not giving
# --- primary_key, String, *optional, uniq primary key, first attribute selecting if not given
# --- attributes, JSON, {field_name: 'DataType'}
# --- validations, JSON, *optional, {validator: 'parameters'}, ActiveRecord Validatiors
# --- callbacks, JSON, *optional, {callback: 'event_name'}, Event Object to notify
# --- settings, JSON, *optional, {key: 'value'}, Customisable options
# --- translations, JSON
# --- i18n, JSON
# --- settings, JSON
# ---- i18n_attributes, keys for translatable attributes
# ---- public_attributes map of json representation
# ---- csv_attributes to download desired columns as csv
# ---- stub_attributes to skip saving data in db
#
# Example
# =======
# Element.create!({
#   name: "User",
#   group: "users",
#   primary_key: "email",
#   attributes: {
#     email: String,
#     first_name: String,
#     last_name: String
#   },
#   validations: {
#     validates_presence_of: %(:email)
#   }
# })
require 'pubs/i18n'
require 'pubs/plv8'

class Element < ActiveRecord::Base

  include Pubs::I18n
  include Pubs::PLV8

  store_accessor :meta, :name, :group, :primary_key,
  :attributes, :validations, :callbacks, :translations, :settings

  localize :meta, :attributes, :validations, :callbacks, :translations, :settings

  STUB = "Stub".freeze

  validates_presence_of :name, :attributes

  before_save :check_naming

  after_save :gen!

  before_destroy :stash
  after_destroy :pop!

  attr_accessor :redefine

  # NOTE: Don't forget, only first level of json is indifferent accessible!
  %w(csv_attributes public_attributes).each { |attr_name|
    class_eval <<-CODE
    def #{attr_name}
      @#{attr_name} ||= (attr_settings = settings.try(:[],:#{attr_name}) ? attr_settings.keys.map(&:to_sym) : persistent_attributes)
    end
    CODE
  }

  def i18n_attributes
    settings.try(:[],:i18n_attributes).try(:map,&:to_sym) || []
  end

  def persistent_attributes
    attributes.select{|name,type| type != STUB}.keys.map(&:to_sym)
  end

  def stub_attributes
    attributes.select{|name,type| type == STUB}.keys.map(&:to_sym)
  end

  def class_defined?
    Object.const_defined?(self.class_name)
  end

  def class_name
    self.destroyed? ? @class_name : self.name
  end

  def atoms
    self.class_name.constantize.all
  end

  def raw_json(options = {})
    json = {}
    self.class.columns.map(&:name).each{|k| json[k] = self.send(k)}
    json = json.delete_if{|k| options[:except].include?(k)} if options[:except]
    json = json.delete_if{|k| !options[:only].include?(k)} if options[:only]
    json.to_json
  end

  def as_json(options = {})
    json = {id: self.id, created_at: self.created_at, updated_at: self.updated_at, atoms_count: self.atoms_count}
    self.class.stored_attributes[:meta].each{|k| json[k] = self.send(k)}
    json
  end

  private

  def stash
    @class_name = self.class_name
  end

  def gen!
    if self.redefine || !class_defined?

      self.redefine = false

      # skip class registration if atom is staticly typed
      if self.attributes[:static].nil?
        # Hmm, removing and readding a constant on the fly
        # not sure but a bit scary
        pop!

        # Generate and define new Element Class
        Object.module_eval atom_code
      end

      define!
    end
  end

  def pop!
    if Object.const_defined? self.class_name
      Object.send :remove_const, self.class_name
    end
  end

  def define!
    # load ActiveRecord translations
    load_translations
    # Freshly baked above!
    klass = self.class_name.safe_constantize
    # data attributes
    klass.send :store_accessor, :data, *self.persistent_attributes
    # localize data attributes if i18n added
    klass.try :localize, :data, *self.i18n_attributes
    # stubs
    klass.send :attr_accessor, *self.stub_attributes

    [:validations,:callbacks].each { |prop|

      next if (hash=self.send(prop)).nil?

      # lazy conversion of hash into ruby code
      klass.class_eval hash.map{ |k,v| k.to_s + v.to_s }.join("\n")
    }

    #create_index_for_pkey self.primary_key

    klass
  end

  def check_naming
    self.group ||= name.tableize
    self.primary_key ||= attributes.keys.first
    self.name = self.name.classify
    self.redefine = self.meta_changed?
  end

  # Loads model translations into I18n::Simple Backend
  def load_translations
    self.translations.each { |k,v|
      I18n.backend.store_translations(I18n.locale, {k => v})
    } if self.translations.present?
  end

  # Create Index
  # def create_index_for_pkey pkey, json = :data
  #   self.class.connection.execute "CREATE INDEX #{pkey}_in_#{json} ON atoms (json_string(#{json},#{self.class.sanitize(pkey)}));"  rescue  nil
  # end

  def atom_code
    <<-CODE
      class #{class_name} < Atom
        include Pubs::I18n
        default_scope -> { where(element_id: '#{self.id}') }
        def self.element
          @@element ||= Element.find_by(id: '#{self.id}')
        end
      end
    CODE
  end

end