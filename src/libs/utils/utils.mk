#*****************************************************************************
#        Makefile Build System for Fawkes: Utilities Build Config
#                            -------------------
#   Created on Mon Mar 10 11:12:14 2008
#   Copyright (C) 2006-2008 by Tim Niemueller, AllemaniACs RoboCup Team
#                 2016 Sven Schneider, Tobias Neumann
#
#*****************************************************************************
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#*****************************************************************************

ifneq ($(wildcard /usr/include/sys/inotify.h $(SYSROOT)/usr/include/*-linux-gnu*/sys/inotify.h),)
  HAVE_INOTIFY=1
  CFLAGS += -DHAVE_INOTIFY
endif

ifneq ($(wildcard $(BUILDCONFDIR)/utils/ipc/shm.h),)
  CFLAGS += -DHAVE_UTILS_IPC_SHM
  HAVE_UTILS_IPC_SHM=1
endif

ifneq ($(wildcard $(BUILDCONFDIR)/utils/time/clock.h),)
  CFLAGS += -DHAVE_UTILS_TIME
  HAVE_UTILS_TIME=1
endif

