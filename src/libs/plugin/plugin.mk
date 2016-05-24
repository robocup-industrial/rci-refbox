#*****************************************************************************
#               Makefile Build System for Fawkes: Config Library
#                            -------------------
#   Created on Tue Jun 21 15:04:39 2007
#   Copyright (C) 2006-2012 by Tim Niemueller, AllemaniACs RoboCup Team
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

ifneq ($(wildcard $(BUILDCONFDIR)/plugin/net/handler.h),)
  CFLAGS += -DHAVE_PLUGIN_NETWORK_HANDLER
	HAVE_PLUGIN_NETWORK_HANDLER=1
endif
