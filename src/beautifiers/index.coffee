_ = require('lodash')
_plus = require('underscore-plus')
Promise = require('bluebird')
Languages = require('../languages/')
path = require('path')
logger = require('../logger')(__filename)
{EventEmitter} = require 'events'

# Lazy loaded dependencies
extend = null
ua = null
fs = null
strip = null
yaml = null
editorconfig = null

# Misc
{allowUnsafeEval} = require 'loophole'
allowUnsafeEval ->
  ua = require("universal-analytics")
pkg = require("../../package.json")
version = pkg.version

# Analytics
trackingId = "UA-52729731-2"

###
Register all supported beautifiers
###
module.exports = class Beautifiers extends EventEmitter
  ###
    List of beautifier names

    To register a beautifier add its name here
  ###
  beautifierNames : [
    'uncrustify'
    'align-yaml'
    'autopep8'
    'coffee-formatter'
    'coffee-fmt'
    'cljfmt'
    'clang-format'
    'crystal'
    'dfmt'
    'elm-format'
    'exfmt'
    'hh_format'
    'htmlbeautifier'
    'csscomb'
    'gherkin'
    'gofmt'
    'goimports'
    'latex-beautify'
    'fortran-beautifier'
    'js-beautify'
    'jscs'
    'eslint'
    'lua-beautifier'
    'nginx-beautify'
    'ocp-indent'
    'perltidy'
    'php-cs-fixer'
    'phpcbf'
    'prettydiff'
    'pybeautifier'
    'pug-beautify'
    'puppet-fix'
    'remark'
    'rubocop'
    'ruby-beautify'
    'rustfmt'
    'sass-convert'
    'sqlformat'
    'stylish-haskell'
    'tidy-markdown'
    'typescript-formatter'
    'vue-beautifier'
    'yapf'
    'erl_tidy'
    'marko-beautifier'
    'formatR'
    'beautysh'
  ]

  ###
    List of loaded beautifiers

    Autogenerated in `constructor` from `beautifierNames`
  ###
  beautifiers : null

  ###
    All beautifier options

    Autogenerated in `constructor`
  ###
  options : null

  ###
    Languages
  ###
  languages : new Languages()

  ###
    Constructor
  ###
  constructor : ->

    # Load beautifiers
    @beautifiers = _.map( @beautifierNames, (name) ->
      Beautifier = require("./#{name}")
      new Beautifier()
    )

    @options = @loadOptions()

  loadOptions : ->
    try
      options = require('../options.json')
      options = _.mapValues(options, (lang) ->
        scope = lang.scope
        tabLength = atom?.config.get('editor.tabLength', scope: scope) ? 4
        softTabs = atom?.config.get('editor.softTabs', scope: scope) ? true
        defaultIndentSize = (if softTabs then tabLength else 1)
        defaultIndentChar = (if softTabs then " " else "\t")
        defaultIndentWithTabs = not softTabs
        if _.has(lang, "properties.indent_size")
          _.set(lang, "properties.indent_size.default", defaultIndentSize)
        if _.has(lang, "properties.indent_char")
          _.set(lang, "properties.indent_char.default", defaultIndentChar)
        if _.has(lang, "properties.indent_with_tabs")
          _.set(lang, "properties.indent_with_tabs.default", defaultIndentWithTabs)
        if _.has(lang, "properties.wrap_attributes_indent_size")
          _.set(lang, "properties.wrap_attributes_indent_size.default", defaultIndentSize)
        return lang
      )
    catch error
      console.error("Error loading options", error)
      options = {}
    return options

  ###
    From https://github.com/atom/notifications/blob/01779ade79e7196f1603b8c1fa31716aa4a33911/lib/notification-issue.coffee#L130
  ###
  encodeURI : (str) ->
    str = encodeURI(str)
    str.replace(/#/g, '%23').replace(/;/g, '%3B')


  getBeautifiers : (language) ->

    # logger.verbose(@beautifiers)
    _.filter( @beautifiers, (beautifier) ->

      # logger.verbose('beautifier',beautifier, language)
      _.includes(beautifier.languages, language)
    )

  getBeautifierForLanguage : (language) ->
    beautifiers = @getBeautifiers(language.name)
    logger.verbose('beautifiers', _.map(beautifiers, 'name'))
    # Select beautifier from language config preferences
    preferredBeautifierName = atom.config.get("atom-beautify.#{language.namespace}.default_beautifier")
    beautifier = _.find(beautifiers, (beautifier) ->
      beautifier.name is preferredBeautifierName
    ) or beautifiers[0]
    return beautifier

  getExtension : (filePath) ->
    if filePath
      return path.extname(filePath).substr(1)

  getLanguages : (grammar, filePath) ->
    # Get language
    fileExtension = @getExtension(filePath)

    if fileExtension
      languages = @languages.getLanguages({grammar, extension: fileExtension})
    else
      languages = @languages.getLanguages({grammar})

    logger.verbose(languages, grammar, fileExtension)

    return languages

  getLanguage : (grammar, filePath) ->
    languages = @getLanguages(grammar, filePath)

    # Check if unsupported language
    if languages.length > 0
      language = languages[0]

    return language

  getOptionsForLanguage : (allOptions, language) ->
    # Options for Language
    selections = (language.fallback or []).concat([language.namespace])
    options = @getOptions(selections, allOptions) or {}

  transformOptions : (beautifier, languageName, options) ->

    # Transform options, if applicable
    beautifierOptions = beautifier.options[languageName]
    if typeof beautifierOptions is "boolean"

      # Language is supported by beautifier
      # If true then all options are directly supported
      # If falsy then pass all options to beautifier,
      # although no options are directly supported.
      return options
    else if typeof beautifierOptions is "object"

      # Transform the options
      transformedOptions = {}


      # Transform for fields
      for field, op of beautifierOptions
        if typeof op is "string"

          # Rename
          transformedOptions[field] = options[op]
        else if typeof op is "function"

          # Transform
          transformedOptions[field] = op(options[field])
        else if typeof op is "boolean"

          # Enable/Disable
          if op is true
            transformedOptions[field] = options[field]
        else if _.isArray(op)

          # Complex function
          [fields..., fn] = op
          vals = _.map(fields, (f) ->
            return options[f]
          )

          # Apply function
          transformedOptions[field] = fn.apply( null , vals)

      # Replace old options with new transformed options
      return transformedOptions
    else
      logger.warn("Unsupported Language options: ", beautifierOptions)
      return options

  trackEvent : (payload) ->
    @track("event", payload)

  trackTiming : (payload) ->
    @track("timing", payload)

  track : (type, payload) ->
    try
      # Check if Analytics is enabled
      if atom.config.get("core.telemetryConsent") is "limited"
        logger.info("Analytics is enabled.")
        # Setup Analytics
        unless atom.config.get("atom-beautify.general._analyticsUserId")
          uuid = require("node-uuid")
          atom.config.set "atom-beautify.general._analyticsUserId", uuid.v4()
        # Setup Analytics User Id
        userId = atom.config.get("atom-beautify.general._analyticsUserId")
        @analytics ?= new ua(trackingId, userId, {
          headers: {
            "User-Agent": navigator.userAgent
          }
        })
        @analytics[type](payload).send()
      else
        logger.info("Analytics is disabled.")
    catch error
      logger.error(error)


  beautify : (text, allOptions, grammar, filePath, {onSave, language} = {}) ->
    return Promise.all(allOptions)
    .then((allOptions) =>
      return new Promise((resolve, reject) =>
        logger.debug('beautify', text, allOptions, grammar, filePath, onSave, language)
        logger.verbose(allOptions)

        language ?= @getLanguage(grammar, filePath)
        fileExtension = @getExtension(filePath)

        # Check if unsupported language
        if !language
          unsupportedGrammar = true

          logger.verbose('Unsupported language')

          # Check if on save
          if onSave
            # Ignore this, as it was just a general file save, and
            # not intended to be beautified
            return resolve( null )
        else
          logger.verbose("Language #{language.name} supported")

          # Get language config
          langDisabled = atom.config.get("atom-beautify.#{language.namespace}.disabled")

          # Beautify!
          unsupportedGrammar = false

          # Check if Language is disabled
          if langDisabled
            logger.verbose("Language #{language.name} is disabled")
            return resolve( null )

          # Get more language config
          beautifyOnSave = atom.config.get("atom-beautify.#{language.namespace}.beautify_on_save")

          # Verify if beautifying on save
          if onSave and not beautifyOnSave
            logger.verbose("Beautify on save is disabled for language #{language.name}")
            # Saving, and beautify on save is disabled
            return resolve( null )

          # Options for Language
          options = @getOptionsForLanguage(allOptions, language)

          # Get Beautifier
          logger.verbose(grammar, language)

          logger.verbose("language options: #{JSON.stringify(options, null, 4)}")

          logger.verbose(language.name, filePath, options, allOptions)

          # Check if unsupported language
          beautifier = @getBeautifierForLanguage(language)
          if not beautifier?
            unsupportedGrammar = true
            logger.verbose('Beautifier for language not found')
          else
            logger.verbose('beautifier', beautifier.name)

            # Apply language-specific option transformations
            options = @transformOptions(beautifier, language.name, options)

            # Beautify text with language options
            @emit "beautify::start"

            context =
              filePath: filePath
              fileExtension: fileExtension

            startTime = new Date()
            beautifier.loadExecutables()
              .then((executables) ->
                logger.verbose('executables', executables)
                beautifier.beautify(text, language.name, options, context)
              )
              .then((result) =>
                resolve(result)
                # Track Timing
                @trackTiming({
                  utc: "Beautify" # Category
                  utv: language?.name # Variable
                  utt: (new Date() - startTime) # Value
                  utl: version # Label
                })
                # Track Empty beautification results
                if not result
                  @trackEvent({
                    ec: version, # Category
                    ea: "Beautify:Empty" # Action
                    el: language?.name # Label
                  })
              )
              .catch((error) =>
                logger.error(error)
                reject(error)
                # Track Errors
                @trackEvent({
                  ec: version, # Category
                  ea: "Beautify:Error" # Action
                  el: language?.name # Label
                })
              )
              .finally(=>
                @emit "beautify::end"
              )

        # Check if Analytics is enabled
        @trackEvent({
          ec: version, # Category
          ea: "Beautify" # Action
          el: language?.name # Label
        })
        if onSave
          @trackEvent({
            ec: version, # Category
            ea: "Beautify:OnSave" # Action
            el: language?.name # Label
          })
        else
          @trackEvent({
            ec: version, # Category
            ea: "Beautify:Manual" # Action
            el: language?.name # Label
          })


        if unsupportedGrammar
          if atom.config.get("atom-beautify.general.muteUnsupportedLanguageErrors")
            return resolve( null )
          else
            repoBugsUrl = pkg.bugs.url
            title = "Atom Beautify could not find a supported beautifier for this file"
            detail = """
                     Atom Beautify could not determine a supported beautifier to handle this file with grammar \"#{grammar}\" and extension \"#{fileExtension}\". \
                     If you would like to request support for this file and its language, please create an issue for Atom Beautify at #{repoBugsUrl}
                     """

            atom?.notifications.addWarning(title, {
              detail
              dismissable : true
            })
            return resolve( null )
            )

      )

  findFileResults : {}


  # CLI
  getUserHome : ->
    process.env.HOME or process.env.HOMEPATH or process.env.USERPROFILE
  verifyExists : (fullPath) ->
    fs ?= require("fs")
    ( if fs.existsSync(fullPath) then fullPath else null )



  # Storage for memoized results from find file
  # Should prevent lots of directory traversal &
  # lookups when liniting an entire project
  ###
    Searches for a file with a specified name starting with
    'dir' and going all the way up either until it finds the file
    or hits the root.

    @param {string} name filename to search for (e.g. .jshintrc)
    @param {string} dir directory to start search from (default:
    current working directory)
    @param {boolean} upwards should recurse upwards on failure? (default: true)

    @returns {string} normalized filename
  ###
  findFile : (name, dir, upwards = true) ->
    path ?= require("path")
    dir = dir or process.cwd()
    filename = path.normalize(path.join(dir, name))
    return @findFileResults[filename] if @findFileResults[filename] isnt undefined
    parent = path.resolve(dir, "../")
    if @verifyExists(filename)
      @findFileResults[filename] = filename
      return filename
    if dir is parent
      @findFileResults[filename] = null
      return null
    if upwards
      findFile name, parent
    else
      return null


  ###
    Tries to find a configuration file in either project directory
    or in the home directory. Configuration files are named
    '.jsbeautifyrc'.

    @param {string} config name of the configuration file
    @param {string} file path to the file to be linted
    @param {boolean} upwards should recurse upwards on failure? (default: true)

    @returns {string} a path to the config file
  ###
  findConfig : (config, file, upwards = true) ->
    path ?= require("path")
    dir = path.dirname(path.resolve(file))
    envs = @getUserHome()
    home = path.normalize(path.join(envs, config))
    proj = @findFile(config, dir, upwards)
    logger.verbose(dir, proj, home)
    return proj if proj
    return home if @verifyExists(home)
    null
  getConfigOptionsFromSettings : (langs) ->
    config = atom.config.get('atom-beautify')
    options = _.pick(config, langs)

  # Look for .jsbeautifierrc in file and home path, check env variables
  getConfig : (startPath, upwards = true) ->
    # console.log('getConfig', startPath, upwards)
    # Verify that startPath is a string
    startPath = ( if ( typeof startPath is "string") then startPath else "")
    return {} unless startPath


    # Get the path to the config file
    configPath = @findConfig(".jsbeautifyrc", startPath, upwards)
    logger.verbose('configPath', configPath, startPath, upwards)
    externalOptions = undefined
    if configPath
      fs ?= require("fs")
      try
        contents = fs.readFileSync(configPath,
          encoding : "utf8"
        )
      catch error
        contents = null #file isnt available anymore
      unless contents
        externalOptions = {}
      else
        try
          strip ?= require("strip-json-comments")
          externalOptions = JSON.parse(strip(contents))
        catch e
          jsonError = e.message
          logger.debug "Failed parsing config as JSON: " + configPath
          # Attempt as YAML
          try
            yaml ?= require("yaml-front-matter")
            externalOptions = yaml.safeLoad(contents)
          catch e
            title = "Atom Beautify failed to parse config as JSON or YAML"
            detail = """
                     Parsing '.jsbeautifyrc' at #{configPath}
                     JSON: #{jsonError}
                     YAML: #{e.message}
                     """
            atom?.notifications.addWarning(title, {
              detail
              dismissable : true
            })
            logger.debug "Failed parsing config as YAML and JSON: " + configPath
            externalOptions = {}
    else
      externalOptions = {}
    return externalOptions

  getOptionsForPath : (editedFilePath, editor) ->
    languageNamespaces = @languages.namespaces


    # Editor Options
    editorOptions = {}
    if editor?

      # Get current Atom editor configuration
      isSelection = !!editor.getSelectedText()
      softTabs = editor.softTabs
      tabLength = editor.getTabLength()
      editorOptions =
        indent_size : ( if softTabs then tabLength else 1)
        indent_char : ( if softTabs then " " else "\t")
        indent_with_tabs : not softTabs

    # From Package Settings
    configOptions = @getConfigOptionsFromSettings(languageNamespaces)


    # Get configuration in User's Home directory
    userHome = @getUserHome()


    # FAKEFILENAME forces `path` to treat as file path and its parent directory
    # is the userHome. See implementation of findConfig
    # and how path.dirname(DIRECTORY) returns the parent directory of DIRECTORY
    homeOptions = @getConfig(path.join(userHome, "FAKEFILENAME"), false)
    if editedFilePath?

      # Handle EditorConfig options
      # http://editorconfig.org/
      editorconfig ?= require('editorconfig')
      editorConfigOptions = editorconfig.parse(editedFilePath)
      .then((editorConfigOptions) ->

        logger.verbose('editorConfigOptions', editorConfigOptions)

        # Transform EditorConfig to Atom Beautify's config structure and naming
        if editorConfigOptions.indent_style is 'space'
          editorConfigOptions.indent_char = " "

        # if (editorConfigOptions.indent_size)
        # editorConfigOptions.indent_size = config.indent_size
        else if editorConfigOptions.indent_style is 'tab'
          editorConfigOptions.indent_char = "\t"
          editorConfigOptions.indent_with_tabs = true
          if (editorConfigOptions.tab_width)
            editorConfigOptions.indent_size = editorConfigOptions.tab_width

        # Nest options under _default namespace
        return {
          _default:
            editorConfigOptions
          }
      )

      # Get all options in configuration files from this directory upwards to root
      projectOptions = []
      p = path.dirname(editedFilePath)


      # Check if p is root (top directory)
      while p isnt path.resolve(p, "../")

        # Get config for p
        pf = path.join(p, "FAKEFILENAME")
        pc = @getConfig(pf, false)

        isNested = @isNestedOptions(pc)
        unless isNested
          pc = {
            _default: pc
          }

        # Add config for p to project's config options
        projectOptions.push(pc)

        # logger.verbose p, pc
        # Move upwards
        p = path.resolve(p, "../")
    else
      editorConfigOptions = {}
      projectOptions = []

    # Combine all options together
    allOptions = [
      {
        _default:
          editorOptions
      },
      configOptions,
      {
        _default:
          homeOptions
      },
      editorConfigOptions
    ]
    # Reverse and add projectOptions to all options
    projectOptions.reverse()
    allOptions = allOptions.concat(projectOptions)

    # logger.verbose(allOptions)
    return allOptions

  isNestedOptions : (currOptions) ->
    containsNested = false
    key = undefined

    # Check if already nested under _default
    if currOptions._default
      return true

    # Check to see if config file uses nested object format to split up js/css/html options
    for key of currOptions

      # Check if is supported language
      if _.indexOf(@languages.namespaces, key) >= 0 and typeof currOptions[key] is "object" # Check if nested object (more options in value)
        containsNested = true
        break # Found, break out of loop, no need to continue

    return containsNested

  getOptions : (selections, allOptions) =>
    self = this
    _ ?= require("lodash")
    extend ?= require("extend")

    logger.verbose('getOptions selections', selections, allOptions)

    # logger.verbose(selection, allOptions);
    # Reduce all options into correctly merged options.
    options = _.reduce(allOptions, (result, currOptions) =>
      collectedConfig = currOptions._default or {}
      containsNested = @isNestedOptions(currOptions)
      logger.verbose(containsNested, currOptions)
      # logger.verbose(containsNested, currOptions);

      # Create a flat object of config options if nested format was used
      unless containsNested
        # _.merge collectedConfig, currOptions
        currOptions = {
          _default: currOptions
        }

      # Merge with selected options
      # where `selection` could be `html`, `js`, 'css', etc
      for selection in selections
        # Merge current options on top of fallback options
        logger.verbose('options', selection, currOptions[selection])
        _.merge collectedConfig, currOptions[selection]
        logger.verbose('options', selection, collectedConfig)

      extend result, collectedConfig
    , {})


    # TODO: Clean.
    # There is a bug in nopt
    # See https://github.com/npm/nopt/issues/38
    # logger.verbose('pre-clean', JSON.stringify(options));
    # options = cleanOptions(options, knownOpts);
    # logger.verbose('post-clean', JSON.stringify(options));
    options
