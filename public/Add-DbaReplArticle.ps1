function Add-DbaReplArticle {
    <#
    .SYNOPSIS
        Add an article configuration to a publication in a database on the SQL Server instance(s).

    .DESCRIPTION
        Add an article configuration to a publication in a database on the SQL Server instance(s).

    .PARAMETER SqlInstance
        The SQL Server instance(s) for the publication.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The publication database to apply the article configuration to be replicated.

    .PARAMETER Publication
        The name of the publication.

    .PARAMETER Schema
        Schema where the article to be added is found.
        Default is dbo.

    .PARAMETER Name
        The name of the object to add as an article.

    .PARAMETER Filter
        Sets the where clause used to filter the article horizontally, e.g., DiscontinuedDate IS NULL
        E.g. City = 'Seattle'

    .PARAMETER CreationScriptOptions
        Options for the creation script.
        Use New-DbaReplCreationScriptOptions to create this object.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: repl, Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/define-an-article?view=sql-server-ver16#RMOProcedure

    .LINK
        https://dbatools.io/Add-DbaReplArticle

    .EXAMPLE
        PS C:\> Add-DbaReplArticle -SqlInstance mssql1 -Database Northwind -Publication PubFromPosh -Name TableToRepl

        Adds the TableToRepl table to the PubFromPosh publication from mssql1.Northwind

    .EXAMPLE
        PS C:\> $article = @{
                    SqlInstance           = "mssql1"
                    Database              = "pubs"
                    Publication           = "testPub"
                    Name                  = "publishers"
                    Filter                = "city = 'seattle'"
                }
        PS C:\> Add-DbaReplArticle @article -EnableException

        Adds the publishers table to the TestPub publication from mssql1.Pubs with a horizontal filter of only rows where city = 'seattle.

    .EXAMPLE
        PS C:\> $cso = New-DbaReplCreationScriptOptions -Options NonClusteredIndexes, Statistics
        PS C:\> $article = @{
                    SqlInstance           = 'mssql1'
                    Database              = 'pubs'
                    Publication           = 'testPub'
                    Name                  = 'stores'
                    CreationScriptOptions = $cso
                }
        PS C:\> Add-DbaReplArticle @article -EnableException

        Adds the stores table to the testPub publication from mssql1.pubs with the NonClusteredIndexes and Statistics options set
        includes default options.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Database,
        [Parameter(Mandatory)]
        [string]$Publication,
        [string]$Schema = 'dbo',
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Filter,
        [PSObject]$CreationScriptOptions,
        [switch]$EnableException
    )
    process {

        # Check that $CreationScriptOptions is a valid object
        if ($CreationScriptOptions -and ($CreationScriptOptions -isnot [Microsoft.SqlServer.Replication.CreationScriptOptions])) {
            Stop-Function -Message "CreationScriptOptions should be the right type. Use New-DbaReplCreationScriptOptions to create the object" -ErrorRecord $_ -Target $instance -Continue
        }

        if ($Filter -like 'WHERE*') {
            Stop-Function -Message "Filter should not include the word 'WHERE'" -ErrorRecord $_ -Target $instance -Continue
        }

        foreach ($instance in $SqlInstance) {
            try {
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Adding article $Name to publication $Publication on $instance"

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Get the publication details for $Publication")) {

                    $pub = Get-DbaReplPublication -SqlInstance $instance -SqlCredential $SqlCredential -Name $Publication -EnableException:$EnableException
                    if (-not $pub) {
                        Stop-Function -Message "Publication $Publication does not exist on $instance" -ErrorRecord $_ -Target $instance -Continue
                    }
                }
            } catch {
                Stop-Function -Message "Unable to get publication $Publication on $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Create an article object for $Publication which is a $($pub.Type) publication")) {

                    $articleOptions = New-Object Microsoft.SqlServer.Replication.ArticleOptions

                    if ($pub.Type -in ('Transactional', 'Snapshot')) {
                        $article = New-Object Microsoft.SqlServer.Replication.TransArticle
                        $article.Type = $ArticleOptions::LogBased
                    } elseif ($pub.Type -eq 'Merge') {
                        $article = New-Object Microsoft.SqlServer.Replication.MergeArticle
                        $article.Type = $ArticleOptions::TableBased
                    }

                    $article.ConnectionContext = $replServer.ConnectionContext
                    $article.Name = $Name
                    $article.DatabaseName = $Database
                    $article.SourceObjectName = $Name
                    $article.SourceObjectOwner = $Schema
                    $article.PublicationName = $Publication
                }
            } catch {
                Stop-Function -Message "Unable to create article object for $Name to add to $Publication on $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                if ($CreationScriptOptions) {
                    if ($PSCmdlet.ShouldProcess($instance, "Add creation options for article: $Name")) {
                        $article.SchemaOption = $CreationScriptOptions
                    }
                }

                if ($Filter) {
                    if ($PSCmdlet.ShouldProcess($instance, "Add filter for article: $Name")) {
                        $article.FilterClause = $Filter
                    }
                }

                if ($PSCmdlet.ShouldProcess($instance, "Create article: $Name")) {
                    if (-not ($article.IsExistingObject)) {
                        $article.Create()
                    } else {
                        Stop-Function -Message "Article already exists in $Publication on $instance" -ErrorRecord $_ -Target $instance -Continue
                    }

                    if ($pub.Type -in ('Transactional', 'Snapshot')) {
                        $pub.RefreshSubscriptions()
                    }
                }
            } catch {
                Stop-Function -Message "Unable to add article $Name to $Publication on $instance" -ErrorRecord $_ -Target $instance -Continue
            }
            Get-DbaReplArticle -SqlInstance $instance -SqlCredential $SqlCredential -Publication $Publication -Name $Name -EnableException:$EnableException
        }
    }
}