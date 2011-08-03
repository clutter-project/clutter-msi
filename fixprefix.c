#include <windows.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

static const char prefix_header[] = "prefix=";
#define PREFIX_HEADER_LENGTH 7

static const char **argv = NULL;
static int argc = 0;
static int args_buf_size = 0;

static void
add_argument (const char *argument)
{
  if (args_buf_size == 0)
    argv = malloc (sizeof (char *) * (args_buf_size = 8));
  else if (argc + 1 > args_buf_size)
    argv = realloc (argv, sizeof (char *) * (args_buf_size *= 2));

  argv[argc++] = argument;
}

static void
split_arguments (char *cmd_line)
{
  char *cmd_line_copy = malloc (strlen (cmd_line) + 1);
  char *out_p = cmd_line_copy;
  BOOL in_quotes = FALSE;
  BOOL in_arg = FALSE;

  while (TRUE)
    {
      if (*cmd_line == '\0' || (!in_quotes && *cmd_line == ' '))
        {
          if (in_arg)
            {
              *(out_p++) = '\0';
              in_arg = FALSE;
            }
          if (*cmd_line == '\0')
            break;
        }
      else if (*cmd_line == '"')
        {
          if (in_quotes)
            in_quotes = FALSE;
          else
            {
              if (!in_arg)
                {
                  add_argument (out_p);
                  in_arg = TRUE;
                }

              in_quotes = TRUE;
            }
        }
      else
        {
          if (!in_arg)
            {
              add_argument (out_p);
              in_arg = TRUE;
            }

          *(out_p++) = *cmd_line;
        }

      cmd_line++;
    }
}

static BOOL
get_file_contents (const char *filename,
                   char **contents_out,
                   size_t *size_out)
{
  int length = 0;
  int buf_size = 0;
  char *buf = NULL;
  FILE *in_file = NULL;
  size_t got;

  if ((in_file = fopen (filename, "rb")) == NULL)
    {
      fprintf (stderr, "Error opening %s: %s\n", filename, strerror (errno));
      goto error;
    }

  while (TRUE)
    {
      int to_read;

      if (buf_size - length < 1024)
        {
          char *new_buf;

          if (buf_size == 0)
            new_buf = malloc (buf_size = 1024);
          else
            new_buf = realloc (buf, buf_size *= 2);
          if (new_buf == NULL)
            {
              fprintf (stderr, "Out of memory\n");
              goto error;
            }
          buf = new_buf;
        }

      to_read = buf_size - length;

      got = fread (buf + length, 1, to_read, in_file);
      length += got;

      if (got < to_read)
        {
          if (ferror (in_file))
            {
              fprintf (stderr, "error reading %s\n", filename);
              goto error;
            }

          break;
        }
    }

  fclose (in_file);
  *contents_out = buf;
  *size_out = length;
  return TRUE;

 error:
  if (buf)
    free (buf);
  if (in_file)
    fclose (in_file);

  return FALSE;
}

static void
output_prefix (const char *prefix,
               FILE *out_file)
{
  while (*prefix)
    {
      if (*prefix == '\\')
        fputc ('/', out_file);
      else
        fputc (*prefix, out_file);
      prefix++;
    }
}

static BOOL
rewrite_file (const char *filename,
              const char *file_buf,
              size_t file_length,
              const char *prefix)
{
  FILE *out_file;
  const char *line_end;

  out_file = fopen (filename, "wb");

  if (out_file == NULL)
    {
      fprintf (stderr, "error opening %s for writing: %s\n",
               filename, strerror (errno));
      return FALSE;
    }

  /* The file should begin with 'prefix=' */
  if (file_length >= PREFIX_HEADER_LENGTH &&
      !memcmp (file_buf, prefix_header, PREFIX_HEADER_LENGTH) &&
      (line_end = memchr (file_buf, '\n', file_length)))
    {
      /* Output the corrected prefix instead */
      fputs ("prefix=\"", out_file);
      output_prefix (prefix, out_file);
      fputc ('"', out_file);
      file_length -= line_end - file_buf;
      file_buf = line_end;
    }

  fwrite (file_buf, 1, file_length, out_file);

  fclose (out_file);

  return TRUE;
}

static char *
get_short_path (const char *long_path)
{
  DWORD length;
  char *short_path;

  length = GetShortPathName (long_path, NULL, 0);

  if (length == 0)
    return NULL;

  short_path = malloc (length);
  if (short_path == NULL)
    return NULL;

  if (GetShortPathName (long_path, short_path, length) == 0)
    {
      free (short_path);
      return NULL;
    }

  return short_path;
}

int CALLBACK
WinMain (HINSTANCE instance,
         HINSTANCE prev_instance,
         char *cmd_line,
         int cmd_show)
{
  char *file_buf;
  char *prefix;
  size_t file_length;
  int i;

  split_arguments (cmd_line);

  if (argc < 2)
    {
      fprintf (stderr, "usage: fixprefix <prefix> <file>...\n");
      return 1;
    }

  prefix = get_short_path (argv[0]);
  if (prefix == NULL)
    {
      fprintf (stderr, "error getting short path\n");
      return 1;
    }

  for (i = 1; i < argc; i++)
    {
      if (!get_file_contents (argv[i], &file_buf, &file_length))
        return 1;

      if (!rewrite_file (argv[i], file_buf, file_length, prefix))
        {
          free (file_buf);
          return 1;
        }

      free (file_buf);
    }

  free (prefix);

  return 0;
}
