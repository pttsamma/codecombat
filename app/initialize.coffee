Backbone.Mediator.setValidationEnabled false
app = require 'application'

channelSchemas =
  'auth': require './schemas/subscriptions/auth'
  'bus': require './schemas/subscriptions/bus'
  'editor': require './schemas/subscriptions/editor'
  'errors': require './schemas/subscriptions/errors'
  'misc': require './schemas/subscriptions/misc'
  'multiplayer': require './schemas/subscriptions/multiplayer'
  'play': require './schemas/subscriptions/play'
  'surface': require './schemas/subscriptions/surface'
  'tome': require './schemas/subscriptions/tome'
  'god': require './schemas/subscriptions/god'
  'scripts': require './schemas/subscriptions/scripts'
  'world': require './schemas/subscriptions/world'

definitionSchemas =
  'bus': require './schemas/definitions/bus'
  'misc': require './schemas/definitions/misc'

init = ->
  setupConsoleLogging()
  watchForErrors()
  setUpIOSLogging()
  path = document.location.pathname
  testing = path.startsWith '/test'
  demoing = path.startsWith '/demo'
  initializeServices() unless testing or demoing
  setUpBackboneMediator()
  app.initialize()
  Backbone.history.start({ pushState: true })
  handleNormalUrls()
  setUpMoment() # Set up i18n for moment
  treemaExt = require 'treema-ext'
  treemaExt.setup()

handleNormalUrls = ->
  # http://artsy.github.com/blog/2012/06/25/replacing-hashbang-routes-with-pushstate/
  $(document).on 'click', "a[href^='/']", (event) ->

    href = $(event.currentTarget).attr('href')

    # chain 'or's for other black list routes
    passThrough = href.indexOf('sign_out') >= 0

    # Allow shift+click for new tabs, etc.
    if !passThrough && !event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey
      event.preventDefault()

      # Remove leading slashes and hash bangs (backward compatablility)
      url = href.replace(/^\//,'').replace('\#\!\/','')

      # Instruct Backbone to trigger routing events
      app.router.navigate url, { trigger: true }

      return false

setUpBackboneMediator = ->
  Backbone.Mediator.addDefSchemas schemas for definition, schemas of definitionSchemas
  Backbone.Mediator.addChannelSchemas schemas for channel, schemas of channelSchemas
  Backbone.Mediator.setValidationEnabled document.location.href.search(/codecombat.com/) is -1
  if webkit?.messageHandlers
    window.iPadSubscriptions = 'application:error': true  # We try to subscribe to this one before it's all set up, so just do it.
    originalPublish = Backbone.Mediator.publish
    Backbone.Mediator.publish = ->
      originalPublish.apply Backbone.Mediator, arguments
      if window.iPadSubscriptions[arguments[0]]
        webkit.messageHandlers.backboneEventHandler?.postMessage channel: arguments[0], event: serializeForIOS(arguments[1] ? {})

setUpMoment = ->
  {me} = require 'lib/auth'
  moment.lang me.get('preferredLanguage', true), {}
  me.on 'change:preferredLanguage', (me) ->
    moment.lang me.get('preferredLanguage', true), {}

initializeServices = ->
  services = [
    './lib/services/filepicker'
    './lib/services/segmentio'
    './lib/services/olark'
    './lib/services/facebook'
    './lib/services/google'
    './lib/services/twitter'
    './lib/services/linkedin'
  ]

  for service in services
    service = require service
    service()

setupConsoleLogging = ->
  unless console.debug
    # Needed for IE10 and earlier
    console.debug = console.log

watchForErrors = ->
  currentErrors = 0
  window.onerror = (msg, url, line, col, error) ->
    return if currentErrors >= 3
    return unless me.isAdmin() or document.location.href.search(/codecombat.com/) is -1 or document.location.href.search(/\/editor\//) isnt -1
    ++currentErrors
    message = "Error: #{msg}<br>Check the JS console for more."
    #msg += "\nLine: #{line}" if line?
    #msg += "\nColumn: #{col}" if col?
    #msg += "\nError: #{error}" if error?
    #msg += "\nStack: #{stack}" if stack = error?.stack
    unless webkit?.messageHandlers  # Don't show these notys on iPad
      noty text: message, layout: 'topCenter', type: 'error', killer: false, timeout: 5000, dismissQueue: true, maxVisible: 3, callback: {onClose: -> --currentErrors}
    Backbone.Mediator.publish 'application:error', message: msg  # For iOS app

window.addIPadSubscription = (channel) ->
  window.iPadSubscriptions[channel] = true

window.removeIPadSubscription = (channel) ->
  window.iPadSubscriptions[channel] = false

setUpIOSLogging = ->
  return unless webkit?.messageHandlers
  for level in ['debug', 'log', 'info', 'warn', 'error']
    do (level) ->
      originalLog = console[level]
      console[level] = ->
        originalLog.apply console, arguments
        try
          webkit?.messageHandlers?.consoleLogHandler?.postMessage level: level, arguments: (a?.toString?() ? ('' + a) for a in arguments)
        catch e
          webkit?.messageHandlers?.consoleLogHandler?.postMessage level: level, arguments: ['could not post log: ' + e]

# This is so hacky... hopefully it's restrictive enough to not be slow.
# We could also keep a list of events we are actually subscribed for and only try to send those over.
seen = null
window.serializeForIOS = serializeForIOS = (obj, depth=3) ->
  return {} unless depth
  root = not seen?
  seen ?= []
  clone = {}
  keysHandled = 0
  for own key, value of obj
    continue if ++keysHandled > 20
    if not value
      clone[key] = value
    else if value is window or value.firstElementChild or value.preventDefault
      null  # Don't include these things
    else if value in seen
      null  # No circular references
    else if _.isArray value
      clone[key] = (serializeForIOS(child, depth - 1) for child in value)
      seen.push value
    else if _.isObject value
      value = value.attributes if value.id and value.attributes
      clone[key] = serializeForIOS value, depth - 1
      seen.push value
    else
      clone[key] = value
  seen = null if root
  clone

$ -> init()
