#
#  ContactViewerController.rb
#  Sidekick
#
#  Created by Adam Elliot on 22/02/09.
#  Copyright (c) 2009 Adam Elliot. All rights reserved.
#

class ContactViewerController

  attr_accessor :imageView, :contactPopUp, :spinner, :whichContact, :username, :password

  def awakeFromNib
    @showing = :new

    @contacts = []
    @contactPopUp.removeAllItems

    loadABContacts
    loadFBContacts
  end
  
  # Actions

  def getContacts(sender)
    loadFBContacts
  end

  def changeContact(sender)
    displayContact @contactPopUp.indexOfSelectedItem
  end

  def updateAllContacts(sender)
    @abContacts.each do |key, value|
      next if @fbContacts[key].nil?
      removeContactAtIndex i
      updateContact key
    end
  end

  def updateEmptyContacts(sender)
    @abContacts.each do |key, value|
      next if value.hasImage || @fbContacts[key].nil?

      i = @contacts.index key
      removeContactAtIndex i
      updateContact key
    end
  end

  def setImage(sender)
    contact = removeContactAtIndex @contactPopUp.indexOfSelectedItem

    # Don't update old images
    return if @whichContact.selectedSegment.intValue == 0
    updateContact contact
  end
  
  def removeContactAtIndex(index)
    @contactPopUp.removeItemAtIndex index
    contact = @contacts[index]
    @contacts.delete_at(index)
    displayContact(@contactPopUp.indexOfSelectedItem)

    contact
  end
  
  def updateContact(key)
    return unless @fbContacts[key].image
    abContact = @abContacts[key].abContact
    abContact.setImageData @fbContacts[key].image.TIFFRepresentation
    ABAddressBook.sharedAddressBook.save
  end

  def displayContact(index)
    contacts = ((@whichContact.selectedSegment.intValue == 0) && @abContacts) || @fbContacts

    if @contacts.length > 0 && contacts[@contacts[index]].image
      imageView.setHidden false
      imageView.setImage(contacts[@contacts[index]].image)
    else
      imageView.setHidden true
    end
  end

  # This function runs synchronously, so you can be sure @abContacts is valid
  # afterwards.
  def loadABContacts
    @abContacts = {}
    contacts = ABAddressBook.sharedAddressBook.people.sort do |x, y|
      x.displayName <=> y.displayName
    end

    contacts.each do |c|
      contact = Contact.contactWithABContact(c)
      @abContacts[contact.displayName.to_sym] = contact
    end
  end

  # This function runs asynchronously, so you cannot use @fbContacts until
  # it's set.
  def loadFBContacts(ids = nil)
    @fbContacts = {}
    path = NSBundle.mainBundle.resourcePath.fileSystemRepresentation

    opts = (ids.nil? && "") || " -p "
    IO.popen("ruby #{File.join(path, "faceport #{opts}#{username.stringValue} #{password.stringValue}")}") do |f|
      if ids.nil?
#    f = File.new(File.join(path, 'faceport.dump'), 'r')
#    begin
      contacts = Marshal.load f.readlines(nil)[0]

      contacts.sort! do |x, y|
        x[:first_name] <=> y[:first_name]
      end

      contacts.each do |c|
        contact = Contact.contactWithFBContact(c)

        @fbContacts[contact.displayName.to_sym] = contact
      end

      facebookContactsLoaded
    end
  end

  # Called once we have loaded all out Facebook contacts, we now can work with
  # both datasets.
  def facebookContactsLoaded
    @fbContacts.delete_if { |key, vakue| @abContacts[key].nil? }

    IO.popen("ruby #{File.join(path, "faceport #{username.stringValue} #{password.stringValue}")}") do |f|
      contacts = Marshal.load f.readlines(nil)[0]

    @contacts = @fbContacts.keys.sort
    @contacts.each { |key| @contactPopUp.addItemWithTitle key }

    displayContact(0)
  end
end

class Contact
  def initialize(props = {}, abContactRef = nil)
    @props = {}.merge props
    # A CIImage*, this is only populated AFTER image is called.
    @image = nil

    @abContact = abContactRef
  end

  def self.contactWithFBContact(fbContact)
    props = {}.merge fbContact
    props[:first_name] = "" unless props[:first_name]
    props[:last_name] = "" unless props[:last_name]

    Contact.new(props)
  end

  def self.contactWithABContact(abContact)
    props = {}
    props[:first_name] = abContact.valueForProperty KABFirstNameProperty
    props[:last_name] = abContact.valueForProperty KABLastNameProperty
    props[:company_name] = abContact.valueForProperty KABOrganizationProperty
    flags = abContact.valueForProperty KABPersonFlags
    props[:is_company] = (flags && ((flags.intValue & KABShowAsMask) == KABShowAsCompany))
    props[:image_data] = abContact.imageData

    Contact.new(props, abContact)
  end

  def abContact
    @abContact
  end

  def displayName
    if @props[:is_company]
      "#{@props[:company_name]}".strip
    else
      "#{@props[:first_name]} #{@props[:last_name]}".strip
    end
  end

  def hasImage
    not (@props[:image_url].nil? && @props[:image_data].nil?)
  end

  def image
    unless @image
      if @props[:image_url]
        url = NSURL.alloc.initWithString @props[:image_url]
        @image = NSImage.alloc.initWithContentsOfURL url
      elsif @props[:image_data]
        @image = NSImage.alloc.initWithData @props[:image_data]
      end
    end
    
    @image
  end
end

class ABPerson

  def displayName
    firstName = valueForProperty KABFirstNameProperty
    lastName = valueForProperty KABLastNameProperty
    companyName = valueForProperty KABOrganizationProperty
    flags = valueForProperty KABPersonFlags

    if (flags && ((flags.intValue & KABShowAsMask) == KABShowAsCompany))
      return companyName if companyName and companyName.length > 0
    end
    
    return "#{firstName} #{lastName}".strip
  end
  
end