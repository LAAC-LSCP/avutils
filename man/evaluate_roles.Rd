% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/evaluate_roles.R
\name{evaluate_roles}
\alias{evaluate_roles}
\title{evaluate speaker roles}
\usage{
evaluate_roles(test, reference, resolution = 1, duration = NULL,
  summarize = TRUE, tiers = list(CHI = c("CHI", paste0("UC", 1:9)), FEM
  = paste0("FA", 1:9), MAL = paste0("MA", 1:9)), test_ignore = NULL,
  ref_ignore = NULL, allspeech = TRUE)
}
\arguments{
\item{test}{character, path to file with annotations in DiViMe (.rttm) format}

\item{reference}{character, path to reference file with annotations in DiViMe (.rttm) format}

\item{resolution}{numeric, the time increment in seconds, by default 1}

\item{duration}{numeric, optional info about the duration of the audio. At its default \code{NULL}, the end of the last annotation is taken as the duration}

\item{summarize}{logical (default is \code{TRUE}), should summary metrics be returned or the detailed frame-by-frame results}

\item{tiers}{a named list that controls which labels/speakers from reference and test annotation are used. The name of each element needs to correspond to the speakers/'tiers' in the \bold{test} file, e.g. \code{CHI}, \code{FEM} and \code{MAL}. The content of each element then lists the corresponding speakers/tiers of the reference. For example, the entry \code{FEM = c("FA1", "FA2")} maps the \code{FEM} speaker in the test file to the \code{FA1} and \code{FA2} tiers in the reference file.}

\item{test_ignore, ref_ignore}{character, the annotation values to be ignored. At its default \code{NULL}, nothing is ignored.}

\item{allspeech}{logical, should the speech detection be taken from \emph{all} tiers, i.e. even those that were ignored by setting \code{tiers=}. Default is \code{TRUE}.}
}
\value{
a data.frame (for \code{summarize = TRUE}) or matrix (for \code{summarize = FALSE})
}
\description{
evaluate speaker roles
}
\examples{
reference <- read_elan(system.file("spanish.eaf", package = "avutils"))
test <- read_rttm(system.file("yunitator_old_spanish.rttm", package = "avutils"))
evaluate_roles(reference = reference, test = test, duration = 180, resolution = 10)
# use for pure speech detection
# not quite working yet...
# test <- read_rttm(system.file("tocomboSad_spanish.rttm", package = "avutils"))
# evaluate_roles(reference = reference, test = test, duration = 180, resolution = 10)
}
