# Unfold
Unfold is a **Capistrano for .net** and/or Windows machines. It gives you the ability to easily create and customize your deployment scenario's without having to resort to complex tools that are hard to automize or difficult to setup. Unfold is _only_ powershell, so there's very little magic going on under the hood. 

For access to the remote machines Unfold depens on [Powershell Remoting](http://msdn.microsoft.com/en-us/library/windows/desktop/ee706585.aspx), with access happening over https. Powershell Remoting allows us to obtain a session to a remote machine on which we can then invoke commands or scripblock, providing an viable alternative to SSH on Windows machines. Check the wiki for instructions on how to setup Powershell Remoting over https.

For structuring the different tasks that need to happen during a deploy we depend on the excellent [psake](https://github.com/psake/psake) library. Psake "avoids the angle-bracket tax associated with executable XML by leveraging the PowerShell syntax in your build scripts. " As a result it also makes a perfect fit for describing deployment steps.

## Installation
Installation is straight-forward. Simply `git clone` this repository into your modules path. 

The following piece of code will do just that:

```posh
   $target = $env:PSModulePath.Split(';')[0]
   Set-Location $target
   git clone https://github.com/thomasvm/unfold.git
```        

Once that's done, you can start using Unfold. 

## Unfoldify-ing a project
Just like Capistrano, configuring an Unfold deployment starts with Unfoldify-ing your project. Tod do so, simply open up a Powershell inside your project and issue the following commands

        Import-Module unfold
        unfoldify

This will create a `deployment` folder, for a full explanation you can skip to the deployment structure section. For getting up and running quickly, check QuickStart

## Quickstart
Now that you project is unfoldified, go through the following steps:

1. check the configuration variables inside the config folder, and adjust them for your project's needs
2. Open a powershell command-line into the deployment folder and execute 

        .\unfold.ps1 deploy -properties @{env="dev"}

   If your default configuration is still set to dev, youc an skip the `-properties` part

3. check the output and adjust the configuration as needed
4. start writing custom extensions by adding psake tasks to the `deploy.ps1` file

## Deployment structure
        deployment
        -> config
            -> dev.ps1
            -> shared.ps1
        -> deploy.ps1
        -> unfold.ps1

Let's see what each of them does:

* *unfold.ps1*:

  this file is for loading the Unfold module and passing the command-line parameters on to it. You start deployment by executing this script. E.g.

        .\unfold.ps1 deploy

  Executes the deploy task (and all depending tasks) 

* *deploy.ps1*

  this file's purpose is to the default tasks, defines any custom task, and/or hooking them onto other tasks to complement the deployment flow. 

* *config* folder

  the config folder contains one file per deployment target, plus one _shared_ configuration file. So it the generated folder, there is one deployemnt environment defined: dev. If you would like to add a staging or a production target, then it's just a matter of add a `staging.ps1` or a `production.ps1` file to the config folder. You can then deploy to one of those environments by calling Unfold in the following way:

        .\unfold.ps1 deploy -properties @{env="staging"}

  this will tell unfold to load the shared + the staging enviromment variables for deployment        

## Configuration
Setting the configuration settings for your deployment happens in the files in the config folder. As mentioned before, there is one `shared.ps1` file for _shared_ configuration settings, and then one file per environment you want to deploy to: `dev.ps1`, `staging.ps1`, `anynameyoudlike.ps1`. Switching environments happens by passing the `env` property to the `unfold.ps1` command.

When you open one of the configuration files, you'll see that it is a concatenation of Set-Config calls. These `Set-Config` calls add properties to a Powershell `$config` object that is accessible in all of the deployment tasks, and that is also available when executing calls on remote machines. (More on that later)

The `shared.ps1` looks more or less like this:

        # Set project name
        Set-Config project "unfold-example"
        
        # Source control
        Set-Config scm git
        Set-Config repository "git@github.com/<your project here>"
        # Set-Config branch "a-branch"
        
        # Default environment to deploy to
        Set-Config default dev

The default `dev.ps1` looks like this:

        Set-Config basePath "<a folder somewhere>"
        
        # local machine
        Set-Config machine "localhost"

As you can see, the `dev.ps1` one contains settings that are environment specific, while the `shared.ps1` file contains settings that will be shared amongst different environments. You're free to alter these settings or to add custom configuration settings should you need them, e.g. the locations of your log files, or connection strings for running a database migration tool

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

        Invoke-Script {
            New-Item -type Directory -Name "logs"
        }

* `Convert-Configuration`        

  Applying .config file [transformations](http://msdn.microsoft.com/en-us/library/dd465326.aspx) from a command-line is overly complex, this helper functions simply needs 3 parameters: the input config, the transform config file and the output path.There's also a -local switch, that allows you to run the transformation locally (in the context where you are executing unfold) or on the deployment target. Executing transformations has never been easier. 

## Customizing
* Every default task is fully overrideable by defining a task that have the same name prefixed with `custom`
* You can _extend_ any task by executing additional tasks before or after them. To do so, you simply need to create a custom task and then use the `Set-AfterTask` or `Set-BeforeTask` functions to make sure they are executed before or after the mentioned task

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

### TODO

* split out scm support creating same functions but with other implementations for git, hg,...
* implement different strategies for getting the code _on the other side_
* Create-AssemblyInfo function for using shared
* ~~function to _unfoldify_ a project~~  
* ~~setupiis task~~
* ~~listversions task~~
* ~~rollback task~~
* ~~cleanup task (keep x versions)~~
