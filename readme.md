# Unfold
Unfold is a complete **deployment solution** for .net based web applications. It gives you the ability to easily create and 
customize your deployment scenario's without having to resort to complex tools that are hard to automate or difficult to setup. 
Unfold is _only_ powershell, so there's very little magic going on under the hood. 

Check [Getting Started](https://github.com/thomasvm/unfold/wiki/Getting-Started) wiki page for installation instructions 
and a quickstart

For updates and info, please check [my blog](http://thomasvm.github.com)
* An [introduction](http://thomasvm.github.com/blog/2012/10/02/introducing-unfold/)
* A full explanation of the [deployment tasks](http://thomasvm.github.com/blog/2012/10/10/the-unfold-tasks/)
* An example extension: [minifying css and javascript](http://thomasvm.github.com/blog/2012/10/11/unfold-task-hooks/)
* [How unfold handles rollback](http://thomasvm.github.com/blog/2012/10/29/how-unfold-handles-rollback/)
* Configuring [local builds](http://thomasvm.github.com//blog/2012/11/12/making-unfold-do-a-local-build/)

## Example
The code snippet below is the _entire_ deployment script for [RaccoonBlog](https://github.com/fitzchak/RaccoonBlog), the
blogging engine behind [Ayende's blog](http://ayende.com).

```posh
## A deployment example for RaccoonBlog, the blog engine that's powering
## blogs like Ayende's

# Configuration
Set-Config project "raccoonblog"

Set-Config scm git
Set-Config repository "https://github.com/fitzchak/RaccoonBlog.git"

# Environment to use when not specified
Set-Config default dev

Set-Config msbuild @('.\code\RaccoonBlog.Web\RaccoonBlog.Web.csproj')

# For custom apppool name
Set-Config apppool "raccoonblog"

# Environments
Set-Environment dev {
    Set-Config basePath "c:\inetpub\wwwroot\raccoon"

    # machine to deploy to
    Set-Config machine "localhost"
}

Set-Environment staging {
    Set-Config basePath "d:\sites\raccoon"
    Set-Config machine "122.123.124.125" # ip address where WinRM is configured
}

# Tasks
Import-DefaultTasks

# Set deploy as default task
task Default -depends "deploy"
```

Executing a deployment is now simply a matter of executing the following PowerShell command in
the folder where your deployment script resides

```posh
.\unfold.ps1 deploy -to staging
```

## Features

* Can deploy to both local and remote machines

* Deployments are based on what's in source control (git, svn) not what's in your working copy

* Rollback

* Deployment flow can be extended and/or customized through task hooks in order to allow advanced scenarios like
    * setting up a static website to server your images, js and css
    * migrating the database
    * modifying Web.config or other configuration files

## Dependencies

There's nothing extra you need to install. Everything comes out-of-the-box.

Unfold depends on the following technologies. They are included in the installation.
* For task configuration we depend on [psake](https://github.com/psake/psake)
* For access to remote machines we used powershell remoting, the SSH for windows. Check the 
  [wiki](https://github.com/thomasvm/unfold/wiki/Setting-up-Powershell-Remoting)for instructions on how to set this up 
  on the deployment target.

## TODO

* hg support, and other scms
* native support for database migration runners like FluentMigrator, DbUp or Entity Framework Migrations
* support for deploying to multiple machines. At the moment there can be only one target.
* Create-AssemblyInfo function for generating a shared assembmy info. Based on [this](https://github.com/ayende/rhino-mocks/blob/master/psake_ext.ps1)
