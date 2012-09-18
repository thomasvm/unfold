# Unfold
Unfold is a **Capistrano for .net** and/or Windows machines. It gives you the ability to easily create and customize your deployment scenario's without having to resort to complex tools that are hard to automize or difficult to setup. Unfold is _only_ powershell, so there's very little magic going on under the hood. 

We depend on two components:
    1. [Powershell Remoting](http://msdn.microsoft.com/en-us/library/windows/desktop/ee706585.aspx) for access to the remote machines, the Windows equivalent of SSH. This allows us to easily execute Powershell scripts on a remote machine. 
    2. The excellent [psake](https://github.com/psake/psake) library for structuring the different tasks that need to happen during a deploy.

What we provide is the following:
    1. a set of functions to make executing powershell code on a remote server very, very easy.
    2. a super simple configuration system
    3. a set of _default_ tasks with sane defaults, easy to extend
    4. some utility functions for typical deployment operation

The result is a deployment solution that:
    1. deploys code that is based on what is in Source Control, not what's in your development folder
    2. makes it very simple to deploy to different environments (dev, staging, production...)
    3. has task hooks. Need some custom setup like installing a windows service? Simply create a psake task for it and hook it up into the standard flow
    4. has no external dependencies except PowerShell
    5. has sane directory structuring and as a result: rollbacks!

## Getting started
The easiest way to get up and running is through nuget. In the Package Manager Console simply type 

```posh
Install-Package unfold
```

Preferrably inside a web project, but this is not required. This creates a `deployment` folder in your project containing:

* a local copy of the unfold powershell library
* an `unfold.ps1` launcher script that can be used to launch deployment commands
* the most important file: `deploy.ps1`, containing configuration settings and deployment tasks for your project

Alternatively, you can also [install Unfold in your user profile](/thomasvm/unfold/wiki/Install-in-your-powershell-profile), and take a slightly different approach.

## Quickstart
Now that unfold is in your project:

1. open the `deploy.ps1` file, it contains both the configuration values and custom tasks for your project. This is what you customize. Note that Visual Studio by default does not have support for PowerShell syntax highlighting, you might want to open the file in another editor or consider installing [PowerGUI extensions](http://visualstudiogallery.msdn.microsoft.com/01516103-d487-4a7e-bb40-c15ec709afa3/) or [TextHighlighterExtensionSetup](http://visualstudiogallery.msdn.microsoft.com/6706b602-6f10-4fd1-8e14-75840f855569/)
2. have a look at the [examples](https://github.com/thomasvm/unfold/tree/master/examples)
3. Open a powershell command-line into the deployment folder and execute (or change the directory of the Package Manager Console to the deployment folder)

	```posh
        .\unfold.ps1 deploy -properties @{env="dev"}
	```		

4. check the output and adjust the configuration as needed
5. customize your deployment by writing custom tasks to the `deploy.ps1` file

## Deployment structure
Now some more detail. All unfold needs are two files

        deployment
        -> deploy.ps1
        -> unfold.ps1

Let's see what each of them does:

* *unfold.ps1*:

  this file is for loading the Unfold module and passing the command-line parameters on to it. You start deployment by executing this script. E.g.

        .\unfold.ps1 deploy

  Executes the deploy task (and all depending tasks) 

* *deploy.ps1*

  this file's has several purposes:
  1. specifying configuration values, some shared, some environment specific
  2. loading the default tasks, defining custom tasks, and/or hooking them onto other tasks to complement the deployment flow. 

## Configuration
The `deploy.ps1` file starts with a set of `Set-Config` calls. These `Set-Config` calls add properties to a Powershell `$config` object that is accessible in all of the deployment tasks, and that is also available when executing calls on remote machines using `Invoke-Script`. 

The `deploy.ps1` looks more or less like this:

```posh
        # Set project name
        Set-Config project "unfold-example"
        
        # Source control
        Set-Config scm git
        Set-Config repository "git@github.com/<your project here>"
        # Set-Config branch "a-branch"
        
        # Default environment to deploy to
        Set-Config default dev
```

For environment specific settings, you can use the `Set-Environment` function. This will instruct Unfold to only load those settings when you are deploying to the specified environment.


```posh
	Set-Environment dev {
	    Set-Config basePath "c:\inetput\wwwroot\unfold\project" 
	    Set-Config machine "localhost"
	}

	Set-Environment staging {
	    Set-Config basePath "d:\deployments\project" 
	    Set-Config machine "123.456.0.78"
	}
```

As you can see, there are two environments specified: dev and staging, with both a different machine and basepath to deploy to.  Once you're deploying to a specific environment these settings will be available on the `$config` object as `$config.basePath` and `$config.machine` when you're writing custom tasks. (See Usage for more info on how to specify the environment when deploying)

You're free to alter these settings or to add custom configuration settings should you need them, e.g. the locations of your log files, or connection strings for running a database migration tool.

## Default tasks
Unfold comes with a set of default tasks (you can list them using the -docs command-line switch). These tasks take care of the typical steps of a deployment flow

* setup: creates the base folder that will contain the different deployments of your application
* updatecode: fetches the code from the code repository
* build: builds the first web project found, or the first solution. You can also specify a custom solution (see config)
* release: copy the build output into a special folder, this will contain all necessary files for your application to run (binaries, dlls, views, css, js,...)
* setupapppool: this will create or update a dedicated application pool for your application
* setupiis: point an IIS website to the release folder
* finalize: make a link call `current` that points to the current release

And then some special tasks:

* listremoteversions: lists all remote versions, can be used by the rollback task
* rollback: points the current website to one of the existing releases
* purgeoldreleases: removes releases that are too old to be kept around

## Usage
Executing Unfold happens through the `unfold.ps1` script. The following options are available

1. Executing a target, the default target (if any) is defined in your `deploy.ps1` script

        .\unfold.ps1 deploy

2. For a list of all available tasks, you can pass in the `-docs` switch

        .\unfold.ps1 -docs

3. Some tasks can have parameters (e.g. rollback) these are passed in using the -properties parameter, combined with a hashtable

        .\unfold.ps1 rollback -properties @{env="production";to=5}

## Important functions        

* `Invoke-Script`

  This is one of the building blocks of Unfold. Basically it allows you to run a Script Block on the target of your deployment. If the target is your local machine, then the script will simply be executed on the `config.basePath` path, if the target is a remote machine, then a remote session is opened (if not already) and the script is executed on the remote machine, also in the `config.basePath` path. This following piece of code for example will create a new `logs` folder on your deployment environment.

```posh
        Invoke-Script {
            New-Item -type Directory -Name "logs"
        }
```

* `Convert-Configuration`        

  Applying .config file [transformations](http://msdn.microsoft.com/en-us/library/dd465326.aspx) from a command-line is overly complex, this helper functions simply needs 3 parameters: the input config, the transform config file and the output path.There's also a -local switch, that allows you to run the transformation locally (in the context where you are executing unfold) or on the deployment target. Executing transformations has never been easier. 

## Customizing
* Every default task is fully overrideable by defining a task that have the same name prefixed with `custom`. For example, if you need to override the default build, simple create a task called `custombuild` and we'll use that instead of the standard implementation.
* You can _extend_ any task by executing additional tasks before or after them. To do so, you simply need to create a custom task and then use the `Set-AfterTask` or `Set-BeforeTask` functions to make sure they are executed before or after the mentioned task

```posh
        # Add custom tasks, for example one to
        # setup logs folder in root
        task createlogs -description "Creates logs folder in root" {
            # Execute in remote location
            Invoke-Script {
                If(-not(Test-Path $config.basePath)) {
                    New-Item -type Directory -Name logs
                }
            }
        }
        
        # Set it to execute after setup
        Set-AfterTask setup createlogs        
```

### TODO

* hg support, and other scms
* Create-AssemblyInfo function for generating a shared assembmy info. Based on [this](https://github.com/ayende/rhino-mocks/blob/master/psake_ext.ps1)
