# Unfold
Unfold is a **Capistrano for .net** and/or Windows machines. It gives you the ability to easily create and customize 
your deployment scenario's without having to resort to complex tools that are hard to automize or difficult to setup. 
Unfold is _only_ powershell, so there's very little magic going on under the hood. 

For updates and info, please check [my blog](http://thomasvm.github.com)
* An [introduction](http://thomasvm.github.com/blog/2012/10/02/introducing-unfold/)
* A full explanation of the [deployment tasks](http://thomasvm.github.com/blog/2012/10/10/the-unfold-tasks/)
* An example extension: [minifying css and javascript](http://thomasvm.github.com/blog/2012/10/11/unfold-task-hooks/)
* [How unfold handles rollback](http://thomasvm.github.com/blog/2012/10/29/how-unfold-handles-rollback/)
* Configuring [local builds](http://thomasvm.github.com//blog/2012/11/12/making-unfold-do-a-local-build/)

Unfold depends on the following technologies
* For task configuration we depend on [psake](https://github.com/psake/psake)
* For access to remote machines we used powershell remoting, the SSH for windows. Check the 
  [wiki](https://github.com/thomasvm/unfold/wiki/Setting-up-Powershell-Remoting)for instructions on how to set this up 
  on the deployment target.

## Installation
There are two ways of installing Unfold

1. The recommended way is to [install Unfold in your user profile](/thomasvm/unfold/wiki/Install-in-your-powershell-profile)
2. Alternatively you can also install Unfold locally inside the project you want to deploy, to do so in the 
   Visual Studio Package Manager Console simply type 

```posh
Install-Package unfold
```
   
   Preferrably inside a web project, but this is not required. This creates a `deployment` folder in your project containing:
   
   * a local copy of the unfold powershell library
   * an `unfold.ps1` launcher script that can be used to launch deployment commands
   * the most important file: `deploy.ps1`, containing configuration settings and deployment tasks for your project

## Quickstart
Now that unfold is in your project:

1. open the `deploy.ps1` file, it contains both the configuration values and custom tasks for your project. This is what you customize. Note that Visual Studio by default does not have support for PowerShell syntax highlighting, you might want to open the file in another editor or consider installing [PowerGUI extensions](http://visualstudiogallery.msdn.microsoft.com/01516103-d487-4a7e-bb40-c15ec709afa3/) or [TextHighlighterExtensionSetup](http://visualstudiogallery.msdn.microsoft.com/6706b602-6f10-4fd1-8e14-75840f855569/)
2. have a look at the [examples](https://github.com/thomasvm/unfold/tree/master/examples)
3. Open a powershell command-line into the deployment folder and execute (or change the directory of the Package Manager Console to the deployment folder)

	```posh
        .\unfold.ps1 deploy
	```		

4. check the output and adjust the configuration as needed
5. customize your deployment by writing custom tasks to the `deploy.ps1` file

## Usage
Executing Unfold happens through the `unfold.ps1` script. The following options are available

1. Executing a target, the default target (if any) is defined in your `deploy.ps1` script

        .\unfold.ps1 deploy

2. For a list of all available tasks, you can pass in the `-docs` switch

        .\unfold.ps1 -docs

3. Some tasks can have parameters (e.g. rollback) these are passed in using the -properties parameter, combined with a hashtable

        .\unfold.ps1 rollback -properties @{to=5} -on production

### TODO

* hg support, and other scms
* native support for database migration runners like FluentMigrator, DbUp or Entity Framework Migrations
* Create-AssemblyInfo function for generating a shared assembmy info. Based on [this](https://github.com/ayende/rhino-mocks/blob/master/psake_ext.ps1)
