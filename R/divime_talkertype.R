#' run the DiViMe talker type module (yunitate)
#'
#' @param audio_loc character, path to the audio files
#' @param divime_loc character, path to the DiViMe directory with a VM
#' @param marvinator logical, run Marvin's version of yunitator, by default \code{FALSE} (for backwards compatibility)
#' @param vmstart logical, perform a check whether the VM is running and if not start it up (by default \code{TRUE}). Turning this off, will speed up the function a little bit, but requires that you are sure that the VM is indeed running in \code{divime_loc}.
#' @param vmshutdown logical, should the VM shut down after the operations are done (by default \code{TRUE})
#' @param messages logical, should the file names of each processed file be printed
#' @param overwrite logical, should output files be overwritten if they already exist (default is \code{FALSE})
#' @return a data.frame with the locations of the created rttm files and some diagnostics
#' @details If \code{marvinator = TRUE} then the output file will be 'yunitator_english_X.rttm', where 'X' is the file name of the audio file. If \code{marvinator = FALSE}, then the resulting file will be named 'yunitator_old_X.rttm'.
#' @export
#' @importFrom stats lm na.omit predict
#'

divime_talkertype <- function(audio_loc,
                              divime_loc,
                              marvinator = FALSE,
                              vmstart = TRUE,
                              vmshutdown = TRUE,
                              messages = TRUE,
                              overwrite = FALSE) {
  # audio_loc = "~/Desktop/test_audio/onefile"
  # divime_loc = "/Volumes/Data/VM2/ooo/DiViMe"
  # vmshutdown = F; messages = TRUE; overwrite = FALSE
  # marvinator = TRUE

  audio_loc <- normalizePath(audio_loc)
  divime_loc <- normalizePath(divime_loc)

  vagrant <- Sys.which("vagrant")

  # check VM state and start if necessary
  if (vmstart) {
    vm_running <- divime_vagrant_state(divime_loc = divime_loc,
                                       what = "status",
                                       silent = TRUE)
    if (vm_running %in% c("running (virtualbox)")) {
      vm_running <- TRUE
    } else {
      vm_running <- FALSE
    }
    if (!vm_running) {
      divime_vagrant_state(divime_loc = divime_loc,
                           what = "start",
                           silent = TRUE)
    }
  }

  paths <- avutils:::handle_filenames(audio_loc = audio_loc,
                                      divime_loc = divime_loc)

  logres <- data.frame(audio = paths$filestoprocess,
                       size = paths$size,
                       processed = FALSE,
                       ptime = NA,
                       outlines = NA,
                       output = NA,
                       audiocopy = NA,
                       audioremove = NA,
                       resultscopy = NA,
                       resultsremove = NA,
                       yuniproblem = NA)

  # create command depending on the desired module
  if (marvinator) {
    cm <- paste0("ssh -c 'yunitate.sh data/ english'")
    fileprefix <- "yunitator_english_"
  } else {
    cm <- paste0("ssh -c 'yunitate.sh data/'")
    fileprefix <- "yunitator_old_"
  }


  # loop through files
  for (i in 1:nrow(logres)) {
    # take time stamp
    t1 <- Sys.time()

    # create names and locations for output rttm
    output_file <- paste0(fileprefix, paths$root_clean[i], ".rttm")
    output_file_ori <- paste0(fileprefix, paths$root[i], ".rttm")
    output_file_to <- normalizePath(paste0(audio_loc, "/", paths$folder[i], output_file_ori),
                                    winslash = "/",
                                    mustWork = FALSE)
    output_file_from <- normalizePath(paste0(divime_loc, "/data/", output_file),
                                      winslash = "/",
                                      mustWork = FALSE)
    # if overwrite = FALSE, continue only if the target file does not yet exist
    # if it already exists, we can skip the processing in the VM
    output_exists <- file.exists(output_file_to)
    if (!(!overwrite & output_exists)) {
      # copy audio file
      logres$audiocopy[i] <- file.copy(from = paths$audiosource[i],
                                       to = paths$audiotarget_clean[i])

      # deal with working directories
      WD <- getwd()
      setwd(divime_loc)

      # run bash command
      xres <- system2(command = vagrant,
                      args = cm,
                      stdout = TRUE,
                      stderr = TRUE)
      setwd(WD)

      # log number of lines in output
      logres$outlines[i] <- length(readLines(output_file_from))

      # copy output back to source location from divime location
      logres$resultscopy[i] <- file.copy(from = output_file_from,
                                         to = output_file_to,
                                         overwrite = overwrite)
      # clean audio file and output from divimi location
      logres$audioremove[i] <- file.remove(paths$audiotarget_clean[i])
      logres$resultsremove[i] <- file.remove(output_file_from)

      logres$output[i] <- output_file_ori
      logres$processed[i] <- TRUE

      # check for yunitator problem and log it
      X <- xres[grep("[[:digit:]]{1,10} Killed", xres)]
      if (length(X) > 0) {
        logres$yuniproblem[i] <- TRUE
        if (messages) message("[POTENTIAL PROBLEM]   :",
                              paths$filestoprocess[i],
                              "  -->  ",
                              output_file)
        message("possibly yunitator problem with file: ",
                paths$filestoprocess[i])
      } else {
        logres$yuniproblem[i] <- FALSE
        if (messages) message(paths$filestoprocess[i],
                              "  -->  ",
                              output_file_ori)
      }

      # clean up
      rm(X, xres)
    }

    # clean up
    rm(output_exists, output_file, output_file_ori, output_file_to)

    t2 <- Sys.time()
    logres$ptime[i] <- as.numeric(round(difftime(t2, t1, units = "min"), 3))

    # predict time left
    temp <- na.omit(logres[, c("ptime", "size")])
    sizes <- logres$size[is.na(logres$ptime)]
    if (nrow(temp) > 1) {
      tempres <- lm(ptime ~ size, temp)
      if (length(sizes) > 0) {
        timeleft <- round(sum(predict(tempres,
                                      newdata = data.frame(size = sizes))),
                          digits = 1)
        cat("expected time until finish: ", timeleft, " minutes\n")
      }
    }
  }

  # shut down if requested
  if (vmshutdown) {
    divime_vagrant_state(divime_loc = divime_loc,
                         what = "halt",
                         silent = TRUE)
  }

  logres
}
