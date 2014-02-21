_       = require("lodash")
fs      = require("fs")
path    = require("path")
async   = require("async")

parse   = require("./parse")


class Module
  constructor : (@name, @fileName, @deps = []) -> 
    @isAnonymous = false
    @isInline = false
    @hasDefine = false



module.exports = traceModule = (startModuleName, config, allModules = [], callback) ->

  resolveModuleName = (moduleName, relativeTo = "") ->

    if moduleName[0] == "."
      return path.join(path.dirname(relativeTo), moduleName)
    else
      return moduleName


  resolveModuleFileName = (moduleName) ->

    if config.paths[moduleName]
      if config.paths[moduleName] == "empty:"
        return
      else
        return path.resolve(config.baseUrl, config.paths[moduleName]) + ".js"
    else
      return path.resolve(config.baseUrl, moduleName) + ".js"



  resolveModules = (moduleNames, callback) ->

    async.mapSeries(moduleNames, resolveModule, callback)
    return


  resolveInlinedModule = (moduleName, deps, fileName, callback) ->

    async.waterfall([
      
      (callback) -> resolveModules(deps, callback)
      
      (modules, callback) -> 
        module = new Module(moduleName, fileName, _.compact(modules))
        module.hasDefine = true
        module.isInline = true
        emitModule(module)
        callback()

    ], callback)
    return


  resolveModule = (moduleName, callback) ->

    module = _.detect(allModules, name : moduleName)
    if module
      callback(null, module)
      return

    fileName = resolveModuleFileName(moduleName)
    if not fileName
      callback()
      return

    module = new Module(moduleName, fileName)

    # console.log("Resolving", moduleName, fileName)

    async.waterfall([

      (callback) -> fs.readFile(fileName, "utf8", callback)

      parse

      (fileData, ast, definitions, callback) ->

        if _.filter(definitions, (def) -> return def.method == "define" and def.moduleName == undefined).length > 1
          callback(new Error("A module must not have more than one anonymous 'define' calls."))
          return

        module.hasDefine = _.any(definitions, (def) -> 
          return def.method == "define" and (def.moduleName == undefined or def.moduleName == moduleName)
        )
        
        async.mapSeries(
          definitions
          (def, callback) ->

            def.deps = def.deps.map( (depName) -> resolveModuleName(depName, def.moduleName ? moduleName) )

            if def.method == "define" and def.moduleName != undefined and def.moduleName != moduleName
              async.waterfall([
                (callback) -> resolveInlinedModule(def.moduleName, def.deps, fileName, callback)
                (callback) -> callback(null, [])
              ], callback)

            else
              resolveModules(def.deps, callback)
            return
          callback
        )


      (unflatModules, callback) ->

        callback(null, _.compact(_.flatten(unflatModules)))


      (depModules, callback) ->

        module.deps.push(depModules...)
        module.isAnonymous = true

        async.waterfall([

          (callback) ->

            additionalDepNames = null

            if shim = config.shim[module.name]
          
              if shim.exports
                module.exports = shim.exports

              if _.isArray(shim)
                additionalDepNames = shim
              else if shim.deps
                additionalDepNames = shim.deps

            if additionalDepNames
              resolveModules(additionalDepNames, callback)
            else
              callback(null, [])


          (depModules, callback) ->

            module.deps.push(depModules...)
            callback(null, emitModule(module))

        ], callback)
        return

    ], callback)
    return


  emitModule = (module) ->

    allModules.push(module)
    return module


  resolveModule(startModuleName, callback)

  return
