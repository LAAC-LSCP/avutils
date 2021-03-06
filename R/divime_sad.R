#' run a DiViMe SAD module
#'
#' @param audio_loc character, path to the audio files
#' @param divime_loc character, path to the DiViMe directory with a VM
#' @param module character, which module to execute (default is \code{"noisemes"}), see details
#' @param splitaudio numeric, should audio files be split into smaller chunks before processing by SAD tool, default is \code{NULL}, see details
#' @param vmstart logical, perform a check whether the VM is running and if not start it up (by default \code{TRUE}). Turning this off, will speed up the function a little bit, but requires that you are sure that the VM is indeed running in \code{divime_loc}.
#' @param vmshutdown logical, should the VM shut down after the operations are done (by default \code{TRUE})
#' @param messages logical, should the file names of each processed file be printed
#' @param overwrite logical, should output files be overwritten if they already exist (default is \code{FALSE})
#' @details \code{module=} sets the SAD module to be used: can be either \code{"noisemes"}, \code{"opensmile"} or \code{"tocombo"}
#'
#' It appears that some of the modules have difficulties with larger audio files (opensmile and noisemes). Hence, setting \code{splitaudio=} to a numeric value will temporarilly split the source audio into chunks of that duration (\code{\link{split_audio}}). Im my experience, a chunk duration of about two minutes solves these issues (e.g. via \code{splitaudio=120}). Note that this step requires the \code{sox} utility available (see \code{\link{set_binaries}} and \code{\link{split_audio}}).
#' @return a data.frame with the locations of the created rttm files and some diagnostics
#' @export
#' @importFrom utils write.table
#'

divime_sad <- function(audio_loc,
                       divime_loc,
                       module = "noisemes",
                       splitaudio = NULL,
                       vmstart = TRUE,
                       vmshutdown = TRUE,
                       messages = TRUE,
                       overwrite = FALSE) {
  # audio_loc = "~/Desktop/test_audio/"
  # divime_loc = "/Volumes/Data/VM2/ooo/DiViMe"
  # vmshutdown = F; messages = TRUE; overwrite = TRUE
  # module = "noisemes"; splitaudio = FALSE

  # check whether sox is available if audio is to be split
  if (!is.null(splitaudio)) {
    allgood <- FALSE
    if (!is.null(getOption("avutils_sox"))) {
      allgood <- TRUE
    }
    if (Sys.which("sox") != "") {
      allgood <- TRUE
    }
    if (!allgood) {
      stop("sox not found for splitting audio files")
    }
    if (splitaudio <= 0) {
      splitaudio <- FALSE
    } else {
      splitdur <- splitaudio
      splitaudio <- TRUE
    }
  } else {
    splitaudio <- FALSE
  }


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
  if (module == "noisemes") cm <- paste0("ssh -c 'noisemesSad.sh data/'")
  if (module == "opensmile") cm <- paste0("ssh -c 'opensmileSad.sh data/'")
  if (module == "tocombo") cm <- paste0("ssh -c 'tocomboSad.sh data/'")

  # loop through files
  for (i in 1:nrow(logres)) {
    # take time stamp
    t1 <- Sys.time()

    # create names and locations for output rttm
    output_file <- paste0(module, "Sad_", paths$root_clean[i], ".rttm")
    output_file_ori <- paste0(module, "Sad_", paths$root[i], ".rttm")
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
      # copy audio file (either entirely or split)
      if (splitaudio) {
        splitfiles <- split_audio(filein = paths$audiosource[i],
                                  split = splitdur,
                                  pathout = dirname(paths$audiotarget_clean[i]))
        if (sum(!file.exists(splitfiles)) == 0) logres$audiocopy[i] <- TRUE
      } else {
        logres$audiocopy[i] <- file.copy(from = paths$audiosource[i],
                                         to = paths$audiotarget_clean[i])
      }

      # deal with working directories
      WD <- getwd()
      setwd(divime_loc)

      # run bash command
      xres <- system2(command = vagrant,
                      args = cm,
                      stdout = TRUE,
                      stderr = TRUE)
      setwd(WD)

      # remove audio file(s) from divimi location
      if (splitaudio) {
        temp <- file.remove(splitfiles)
        if (sum(temp) == length(splitfiles)) logres$audioremove[i] <- TRUE
        # and get names of rttm files (for merging into single rttm later)
        rttm_files <- list.files(dirname(splitfiles[1]),
                                 pattern = ".rttm",
                                 full.names = TRUE)
      } else {
        logres$audioremove[i] <- file.remove(paths$audiotarget_clean[i])
      }


      # check for success
      success <- TRUE
      if (module == "tocombo") {
        if ("MATLAB:nomem" %in% xres) {
          success <- FALSE
          message("'tocombo' produced MatLab memory error. Split audio file?")
        }
        if (sum(grepl("[[:digit:]]{1,10} Killed", xres)) > 0) {
          success <- FALSE
          message("'tocombo' produced error './get_TOcomboSAD_output_v3'. (process killed). Split audio file?")
        }
      }

      if (success) {
        # merge multiple rttm files if necessary
        if (splitaudio) {
          r <- combine_rttm(rttm_files = rttm_files,
                            split_dur = splitdur,
                            basename = as.character(paths$root[i]))
          write.table(x = r, file = output_file_from, sep = " ",
                      quote = FALSE, row.names = FALSE, col.names = FALSE)
          file.remove(rttm_files)
        }

        # log number of lines in output
        logres$outlines[i] <- length(readLines(output_file_from))

        # copy output back to source location from divime location
        logres$resultscopy[i] <- file.copy(from = output_file_from,
                                           to = output_file_to,
                                           overwrite = overwrite)
        # remove output from divimi location
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
        # additional clean up
        if (module == "opensmile") {
          fn <- paste0(divime_loc, "/data/", paths$root_clean[i], ".txt")
          if (file.exists(fn)) {
            file.remove(fn)
          }
        }
        rm(X)
      }
      # clean up
      rm(xres)
    }

    # clean up
    rm(output_exists, output_file, output_file_from, output_file_ori, output_file_to)

    t2 <- Sys.time()
    logres$ptime[i] <- as.numeric(round(difftime(t2, t1, units = "min"), 3))

    # predict time left
    temp <- na.omit(logres[, c("ptime", "size")])
    sizes <- logres$size[is.na(logres$ptime)]
    if (nrow(temp) > 1) {
      tempres <- lm(ptime ~ size, temp)
      if (length(sizes) > 0) {
        timeleft <- round(sum(predict(tempres, newdata = data.frame(size = sizes))), 1)
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
